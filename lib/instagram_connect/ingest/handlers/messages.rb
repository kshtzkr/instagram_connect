module InstagramConnect
  class Ingest
    module Handlers
      # Inbound DMs, and echoes of messages the business sent from anywhere —
      # this app, the Instagram app, or Meta Business Suite.
      class Messages < Base
        def self.dedupe_key(event)
          event.dig("message", "mid").presence
        end

        # Without Meta's mid there is no way to dedupe this message against its
        # own echo, so it is banked unparsed rather than stored twice.
        def self.requires_dedupe_key?
          true
        end

        def call
          # An echo of a message this system already sent is a CONFIRMATION,
          # not a new message: the send stored the mid first, so create! hits
          # the unique index on [account_id, ig_message_id] and the event is
          # banked failed — then every replay fails again, forever. Enrich the
          # row Meta is echoing rather than duplicating it, and do not
          # re-register it on the conversation (it was registered when sent).
          if (existing = existing_message)
            enrich(existing)
            return existing
          end

          message = InstagramConnect::Message.create!(
            conversation: conversation,
            direction: echo? ? "outbound" : "inbound",
            status: echo? ? "sent" : "received",
            source: echo? ? "operator_app" : "inbound",
            kind: "dm",
            body: payload["text"],
            ig_message_id: mid,
            media_status: media_status,
            media_kind: attachments.first&.dig("type"),
            sent_at: envelope.occurred_at,
            deleted_at: payload["is_deleted"] ? (envelope.occurred_at || Time.current) : nil,
            unsupported: payload["is_unsupported"] ? true : false,
            reply_to_mid: payload.dig("reply_to", "mid"),
            quick_reply_payload: payload.dig("quick_reply", "payload"),
            referral_ref: payload.dig("referral", "ref"),
            referral_source: payload.dig("referral", "source"),
            referral_type: payload.dig("referral", "type"),
            referral_product_id: payload.dig("referral", "product", "id"),
            story_id: story&.dig("id"),
            story_url: story&.dig("url")
          )
          store_attachments(message)
          conversation.register_message(message)
          record_legacy_claim

          # An echo is our own outbound message coming back; firing on_message
          # for it would have the host reply to itself.
          notify(config.on_message, message) unless echo?
          message
        end

        private

        def existing_message
          return if mid.blank?

          InstagramConnect::Message.find_by(account_id: conversation.account_id,
                                            ig_message_id: mid)
        end

        # Fill only what the original write could not know — Meta's clock, the
        # media it processed, the story it was a reply to. Direction, status,
        # source and body stay as first written: an echo must not rewrite a
        # CMS-sent message into one that looks sent from the phone.
        def enrich(message)
          message.sent_at ||= envelope.occurred_at
          message.media_status ||= media_status
          message.media_kind ||= attachments.first&.dig("type")
          message.story_id ||= story&.dig("id")
          message.story_url ||= story&.dig("url")
          message.save! if message.changed?
          store_attachments(message) if message.attachments.none?
          message
        end

        def payload
          event["message"] || {}
        end

        def mid
          payload["mid"].to_s
        end

        def echo?
          payload["is_echo"] ? true : false
        end

        def attachments
          Array(payload["attachments"])
        end

        # An unsupported message has nothing fetchable behind it, and Instagram
        # CDN links expire with no way to ask again — so the verdict is decided
        # here, before the insert, and the row is born in its final state.
        def media_status
          return "unavailable" if payload["is_unsupported"]

          attachments.any? { |a| a.dig("payload", "url").present? } ? "pending" : "none"
        end

        # Rows are written in one insert_all so the bubble is born in its final
        # state: one create, one broadcast, no flicker as files resolve. Each
        # fetch is its own job, so a ten-image message does not serialise
        # behind whichever file is slowest.
        def store_attachments(message)
          return if attachments.empty?

          rows = attachments.each_with_index.map do |attachment, index|
            url = attachment.dig("payload", "url")
            {
              message_id: message.id, position: index,
              kind: attachment["type"].presence || "file",
              source_url: url,
              state: url.present? ? "pending" : "skipped",
              created_at: Time.current, updated_at: Time.current
            }
          end
          InstagramConnect::MessageAttachment.insert_all(rows)

          message.attachments.reload.select(&:fetchable?).each do |attachment|
            InstagramConnect::FetchMediaJob.perform_later(attachment.id)
          end
        end

        # A story reply and a story mention both point at the story they came
        # from; Meta nests it under the attachment payload.
        def story
          @story ||= attachments.filter_map { |a| a.dig("payload", "story") }.first
        end

        # On an echo the customer is the recipient; on an inbound message they
        # are the sender. Either way the conversation is keyed by their IGSID.
        def igsid
          (echo? ? event.dig("recipient", "id") : event.dig("sender", "id")).to_s
        end

        def conversation
          @conversation ||= InstagramConnect::Conversation.locate(account: account, igsid: igsid).tap do |thread|
            # Meta sends the profile on a separate call from the message, so a
            # thread starts life knowing only an opaque id. Fetch it once, when
            # the thread first appears, rather than on every message.
            enqueue_profile_sync(thread) if thread.profile_synced_at.nil?
          end
        end

        def enqueue_profile_sync(thread)
          InstagramConnect::ProfileSyncJob.perform_later(conversation_id: thread.id)
        end

        # The webhook ledger is the dedupe claim now. InboundMessage is kept in
        # step so a host querying it against 0.2.x behaviour still sees every
        # message; it is deprecated and will go at 1.0.
        def record_legacy_claim
          InstagramConnect::InboundMessage.claim(ig_message_id: mid, account_id: account.id)
        end
      end
    end
  end
end

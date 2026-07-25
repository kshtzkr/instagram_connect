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
          conversation.register_message(message)
          record_legacy_claim

          # An echo is our own outbound message coming back; firing on_message
          # for it would have the host reply to itself.
          notify(config.on_message, message) unless echo?
          message
        end

        private

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
          @conversation ||= InstagramConnect::Conversation.locate(account: account, igsid: igsid)
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

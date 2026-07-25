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
            media_status: attachments? ? "pending" : "none"
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

        def attachments?
          Array(payload["attachments"]).any?
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

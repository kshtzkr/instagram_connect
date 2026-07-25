module InstagramConnect
  class Ingest
    module Handlers
      # The customer arrived through an ig.me link, an ad, or a product tag.
      # A referral opens the 24-hour messaging window even before they type
      # anything, so it has to bump the thread's activity.
      #
      # Only a standalone referral reaches here — one nested inside a message
      # or postback stays with its parent event (see Registry).
      class MessagingReferral < Base
        def self.dedupe_key(event)
          ref = event.dig("referral", "ref").presence or return nil

          "#{event.dig('sender', 'id')}:#{ref}:#{event['timestamp']}"
        end

        def call
          conversation.register_referral(ref: payload["ref"], at: referred_at)
          conversation
        end

        private

        def payload
          event["referral"] || {}
        end

        def igsid
          event.dig("sender", "id").to_s
        end

        def referred_at
          envelope.occurred_at || Time.current
        end

        def conversation
          @conversation ||= InstagramConnect::Conversation.locate(account: account, igsid: igsid)
        end
      end
    end
  end
end

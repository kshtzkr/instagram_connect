module InstagramConnect
  class Ingest
    module Handlers
      # A read receipt: the customer has seen everything up to this message.
      class MessagingSeen < Base
        def self.dedupe_key(event)
          mid = event.dig("read", "mid").presence or return nil

          "#{event.dig('sender', 'id')}:#{mid}"
        end

        def call
          conversation.mark_read_by_customer(at: seen_at, mid: mid)
          conversation
        end

        private

        def mid
          event.dig("read", "mid").to_s
        end

        def igsid
          event.dig("sender", "id").to_s
        end

        def seen_at
          envelope.occurred_at || Time.current
        end

        def conversation
          @conversation ||= InstagramConnect::Conversation.locate(account: account, igsid: igsid)
        end
      end
    end
  end
end

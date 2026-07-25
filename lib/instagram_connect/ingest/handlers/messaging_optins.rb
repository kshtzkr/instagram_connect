module InstagramConnect
  class Ingest
    module Handlers
      # The customer opted in to notification messages. There is nothing to
      # store on the thread beyond the fact that they interacted — the opt-in
      # token itself lives in the banked event, where a host that implements
      # recurring notifications can read it without the gem taking a position
      # on how that should work.
      class MessagingOptins < Base
        def self.dedupe_key(event)
          sender = event.dig("sender", "id").presence or return nil

          "#{sender}:#{event['timestamp']}"
        end

        def call
          conversation.register_event(opted_in_at)
          conversation
        end

        private

        def igsid
          event.dig("sender", "id").to_s
        end

        def opted_in_at
          envelope.occurred_at || Time.current
        end

        def conversation
          @conversation ||= InstagramConnect::Conversation.locate(account: account, igsid: igsid)
        end
      end
    end
  end
end

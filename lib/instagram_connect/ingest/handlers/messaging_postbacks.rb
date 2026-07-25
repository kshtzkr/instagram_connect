module InstagramConnect
  class Ingest
    module Handlers
      # A tap on an ice breaker, a persistent-menu item, or a template button.
      # Postbacks carry no message of their own, so there is nothing to persist
      # yet — the host callback is the whole point.
      class MessagingPostbacks < Base
        def self.dedupe_key(event)
          event.dig("postback", "mid").presence
        end

        def call
          notify(config.on_postback, {
            account_id: account.id,
            sender_id: event.dig("sender", "id"),
            payload: event.dig("postback", "payload"),
            title: event.dig("postback", "title")
          })
          nil
        end
      end
    end
  end
end

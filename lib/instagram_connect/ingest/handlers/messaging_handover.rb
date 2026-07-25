module InstagramConnect
  class Ingest
    module Handlers
      # Thread control moving between apps — typically between this app and the
      # Page Inbox a human operator uses.
      #
      # This matters beyond bookkeeping: the Send API rejects a message on a
      # thread another app owns, so a send has to read thread_owner_app_id
      # first rather than discovering it as an opaque API error.
      class MessagingHandover < Base
        CONTROL_KEYS = %w[pass_thread_control take_thread_control request_thread_control].freeze

        def self.dedupe_key(event)
          sender = event.dig("sender", "id")
          key = CONTROL_KEYS.find { |k| event[k] }
          return nil if key.nil?

          [ sender, event["timestamp"], key, event.dig(key, "new_owner_app_id") ].compact.join(":")
        end

        def call
          conversation.register_thread_control(owner_app_id: new_owner_app_id, at: handed_over_at)
          conversation
        end

        private

        def control_key
          @control_key ||= CONTROL_KEYS.find { |key| event[key] }
        end

        # A pass names the app receiving control. A take is the Page Inbox
        # seizing it, so control lands with Meta's own app rather than a named
        # one; recording nil is honest — we know we no longer own the thread.
        def new_owner_app_id
          event.dig(control_key.to_s, "new_owner_app_id")
        end

        def igsid
          event.dig("sender", "id").to_s
        end

        def handed_over_at
          envelope.occurred_at || Time.current
        end

        def conversation
          @conversation ||= InstagramConnect::Conversation.locate(account: account, igsid: igsid)
        end
      end
    end
  end
end

module InstagramConnect
  class Ingest
    module Handlers
      # A handler turns one webhook event into persisted rows and returns the
      # row it produced (or nil), which the dispatcher records on the ledger so
      # an operator can trace an event to its result.
      #
      # Subclasses implement `.dedupe_key` and `#call`.
      class Base
        # Meta's own identifier for this event, used as the dedupe claim. Nil
        # means the event carries no stable id and the dispatcher falls back to
        # hashing the payload.
        def self.dedupe_key(_event)
          nil
        end

        # The host callback this handler wants fired, and its argument. Read by
        # the dispatcher *after* `#call` returns, so the callback runs outside
        # the handler in its own rescue: a host hook must never roll back an
        # ingest whose data is already stored.
        attr_reader :notification

        def initialize(envelope)
          @envelope = envelope
          @notification = nil
        end

        def call
          raise NotImplementedError
        end

        private

        attr_reader :envelope

        def account
          envelope.account
        end

        def event
          envelope.event
        end

        def config
          envelope.config
        end

        def notify(handler, argument)
          @notification = [ handler, argument ]
          argument
        end
      end
    end
  end
end

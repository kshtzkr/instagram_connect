module InstagramConnect
  class Ingest
    module Handlers
      # Anything the gem does not parse yet, or an entry belonging to no
      # connected account. The event is banked verbatim rather than dropped:
      # Meta never re-delivers, so replaying the row later is the only way to
      # recover it once a handler exists.
      #
      # The dispatcher marks these `unhandled` without calling `#call` — this
      # class exists so the registry always resolves to something, and so the
      # ledger records which handler was chosen.
      class Unknown < Base
        def call
          nil
        end
      end
    end
  end
end

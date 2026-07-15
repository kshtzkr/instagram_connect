module InstagramConnect
  # Persists a verified webhook payload off the request path so the controller
  # can ACK Meta immediately.
  class IngestJob < ApplicationJob
    queue_as :default

    def perform(payload)
      Ingest.call(payload: payload)
    end
  end
end

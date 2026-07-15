module InstagramConnect
  # Receives Meta webhooks. Inherits ActionController::Base directly (not the
  # engine ApplicationController) so it bypasses the host's session auth and
  # CSRF, and instead authenticates the GET handshake by verify_token and the
  # POST body by HMAC signature. ACKs fast and hands persistence to a job.
  class WebhooksController < ActionController::Base
    skip_forgery_protection

    # Rails 8 ships `rate_limit`; on 7.1 it's absent, so guard it. The false
    # branch can't execute under a Rails 8 test run.
    # simplecov:disable
    if respond_to?(:rate_limit)
      rate_limit to: 300, within: 1.minute, by: -> { request.remote_ip }, name: "instagram_connect_webhook"
    end
    # simplecov:enable

    # GET — Meta's subscription verification handshake.
    def verify
      if valid_verification?
        render plain: params["hub.challenge"].to_s
      else
        head :forbidden
      end
    end

    # POST — a batch of events. Verify the signature, then enqueue ingestion.
    def receive
      unless SignatureVerifier.valid?(raw_body: request.raw_post, signature: request.headers["X-Hub-Signature-256"])
        return head :unauthorized
      end

      payload = parse_json(request.raw_post)
      return head :bad_request if payload.nil?

      IngestJob.perform_later(payload)
      head :ok
    end

    private

    def valid_verification?
      token = InstagramConnect.configuration.verify_token.to_s
      return false if token.empty?

      params["hub.mode"] == "subscribe" && params["hub.verify_token"].to_s == token
    end

    def parse_json(raw)
      JSON.parse(raw.to_s)
    rescue JSON::ParserError
      nil
    end
  end
end

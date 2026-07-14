module InstagramConnect
  # Base class for every error raised by the gem.
  class Error < StandardError; end

  # Raised when the gem is misconfigured — an unknown auth_path, or a required
  # secret (app_id / app_secret / verify_token) missing at the point of use.
  class ConfigurationError < Error; end

  # Raised when the Meta Graph API returns a non-success response. Carries the
  # HTTP status, Meta's application-level error code, and any retry hint so
  # callers (and the Result object) can react without re-parsing the body.
  class ApiError < Error
    attr_reader :status, :error_code, :retry_after

    def initialize(message, status: nil, error_code: nil, retry_after: nil)
      super(message)
      @status = status
      @error_code = error_code
      @retry_after = retry_after
    end
  end

  # Raised when an inbound webhook fails HMAC signature verification.
  class SignatureError < Error; end
end

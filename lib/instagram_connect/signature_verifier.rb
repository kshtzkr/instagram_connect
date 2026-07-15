require "openssl"

module InstagramConnect
  # Verifies Meta's `X-Hub-Signature-256` header: HMAC-SHA256 of the raw request
  # body keyed by the app secret, compared in constant time. This is how the
  # webhook authenticates that a POST really came from Meta.
  module SignatureVerifier
    module_function

    def valid?(raw_body:, signature:, app_secret: InstagramConnect.configuration.app_secret)
      return false if signature.to_s.empty? || app_secret.to_s.empty?

      expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', app_secret.to_s, raw_body.to_s)}"
      secure_compare(signature.to_s, expected)
    end

    def secure_compare(given, expected)
      return false unless given.bytesize == expected.bytesize

      OpenSSL.fixed_length_secure_compare(given, expected)
    end
  end
end

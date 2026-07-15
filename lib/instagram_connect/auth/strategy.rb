require "json"
require "uri"
require "httparty"

module InstagramConnect
  module Auth
    # Common interface for a Meta login path. Concrete strategies differ only in
    # the Graph host, the OAuth dialog/exchange endpoints, and the scope set.
    # Subclasses implement the public methods; the shared token-lifetime helper
    # and credential accessors live here.
    class Strategy
      HTTP_TIMEOUT = 30

      def initialize(config)
        @config = config
      end

      # e.g. "https://graph.instagram.com"
      def graph_host
        raise NotImplementedError
      end

      # The scope set requested during OAuth.
      def scopes
        raise NotImplementedError
      end

      # The "log in with…" dialog URL the host redirects the operator to.
      def authorize_url(redirect_uri:, state:)
        raise NotImplementedError
      end

      # Exchange an authorization code for a long-lived token. Returns a hash:
      #   { access_token:, expires_at:, ig_user_id: (optional), page_id: (optional) }
      def exchange_code(code:, redirect_uri:)
        raise NotImplementedError
      end

      # Refresh a long-lived token. Returns { access_token:, expires_at: }.
      # Paths whose tokens don't expire return the token unchanged.
      def refresh_token(access_token:)
        raise NotImplementedError
      end

      private

      attr_reader :config

      def app_id
        value = config.app_id
        raise ConfigurationError, "app_id is not configured" if value.to_s.empty?
        value
      end

      def app_secret
        value = config.app_secret
        raise ConfigurationError, "app_secret is not configured" if value.to_s.empty?
        value
      end

      def graph_version
        config.graph_version
      end

      def expires_at_from(seconds)
        seconds ? Time.now + seconds.to_i : nil
      end
    end
  end
end

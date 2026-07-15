module InstagramConnect
  module Auth
    # "Instagram API with Instagram Login" — talks to graph.instagram.com and
    # needs NO linked Facebook Page. Tokens are 60-day, refreshable. This is
    # Meta's recommended path for new integrations.
    class InstagramLogin < Strategy
      AUTHORIZE_URL = "https://www.instagram.com/oauth/authorize".freeze
      TOKEN_URL = "https://api.instagram.com/oauth/access_token".freeze
      GRAPH = "https://graph.instagram.com".freeze
      DEFAULT_SCOPES = %w[
        instagram_business_basic
        instagram_business_manage_messages
        instagram_business_manage_comments
        instagram_business_content_publish
      ].freeze

      def graph_host
        GRAPH
      end

      def scopes
        DEFAULT_SCOPES
      end

      def authorize_url(redirect_uri:, state:)
        query = {
          client_id: app_id,
          redirect_uri: redirect_uri,
          scope: scopes.join(","),
          response_type: "code",
          state: state
        }
        "#{AUTHORIZE_URL}?#{URI.encode_www_form(query)}"
      end

      def exchange_code(code:, redirect_uri:)
        short = HTTParty.post(TOKEN_URL, timeout: HTTP_TIMEOUT, body: {
          client_id: app_id,
          client_secret: app_secret,
          grant_type: "authorization_code",
          redirect_uri: redirect_uri,
          code: code
        })
        raise ApiError.new("code exchange failed: HTTP #{short.code}", status: short.code) unless short.success?
        short_data = JSON.parse(short.body)

        long = HTTParty.get("#{GRAPH}/access_token", timeout: HTTP_TIMEOUT, query: {
          grant_type: "ig_exchange_token",
          client_secret: app_secret,
          access_token: short_data["access_token"]
        })
        raise ApiError.new("long-lived exchange failed: HTTP #{long.code}", status: long.code) unless long.success?
        long_data = JSON.parse(long.body)

        {
          access_token: long_data["access_token"],
          expires_at: expires_at_from(long_data["expires_in"]),
          ig_user_id: short_data["user_id"]&.to_s
        }
      end

      def refresh_token(access_token:)
        resp = HTTParty.get("#{GRAPH}/refresh_access_token", timeout: HTTP_TIMEOUT, query: {
          grant_type: "ig_refresh_token",
          access_token: access_token
        })
        raise ApiError.new("token refresh failed: HTTP #{resp.code}", status: resp.code) unless resp.success?
        data = JSON.parse(resp.body)
        { access_token: data["access_token"], expires_at: expires_at_from(data["expires_in"]) }
      end
    end
  end
end

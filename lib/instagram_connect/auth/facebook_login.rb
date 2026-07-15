module InstagramConnect
  module Auth
    # "Instagram API with Facebook Login" — talks to graph.facebook.com and
    # requires the Instagram professional account be linked to a Facebook Page
    # inside Business Manager. Long-lived Page / System-User tokens are durable
    # (effectively non-expiring), so refresh is a no-op.
    class FacebookLogin < Strategy
      GRAPH = "https://graph.facebook.com".freeze
      DIALOG = "https://www.facebook.com".freeze
      DEFAULT_SCOPES = %w[
        instagram_basic
        instagram_manage_messages
        instagram_manage_comments
        instagram_content_publish
        pages_show_list
        pages_manage_metadata
        pages_read_engagement
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
        "#{DIALOG}/#{graph_version}/dialog/oauth?#{URI.encode_www_form(query)}"
      end

      def exchange_code(code:, redirect_uri:)
        short = HTTParty.get("#{GRAPH}/#{graph_version}/oauth/access_token", timeout: HTTP_TIMEOUT, query: {
          client_id: app_id,
          client_secret: app_secret,
          redirect_uri: redirect_uri,
          code: code
        })
        raise ApiError.new("code exchange failed: HTTP #{short.code}", status: short.code) unless short.success?
        short_data = JSON.parse(short.body)

        long = HTTParty.get("#{GRAPH}/#{graph_version}/oauth/access_token", timeout: HTTP_TIMEOUT, query: {
          grant_type: "fb_exchange_token",
          client_id: app_id,
          client_secret: app_secret,
          fb_exchange_token: short_data["access_token"]
        })
        raise ApiError.new("long-lived exchange failed: HTTP #{long.code}", status: long.code) unless long.success?
        long_data = JSON.parse(long.body)

        { access_token: long_data["access_token"], expires_at: expires_at_from(long_data["expires_in"]) }
      end

      # Long-lived Page / System-User tokens do not expire; return unchanged so
      # the scheduled refresh job can treat every path uniformly.
      def refresh_token(access_token:)
        { access_token: access_token, expires_at: nil }
      end
    end
  end
end

require "logger"

module InstagramConnect
  # Host-facing configuration, set via InstagramConnect.configure { |c| ... }.
  #
  # +auth_path+ selects which Meta login flow + Graph host the gem talks to:
  #   :instagram_login  -> graph.instagram.com, no Facebook Page required
  #   :facebook_login   -> graph.facebook.com, requires a linked Facebook Page
  #
  # Secrets fall back to ENV so a host can configure entirely through the
  # environment (e.g. container secrets) without an initializer edit.
  class Configuration
    AUTH_PATHS = %i[instagram_login facebook_login].freeze

    attr_accessor :app_id, :app_secret, :verify_token,
                  :graph_version, :redirect_uri, :encrypt_tokens,
                  :parent_controller, :authenticate_with, :current_user_id_resolver,
                  :on_message, :on_comment, :on_postback,
                  :logger, :default_per_page, :inherit_host_layout,
                  :media_max_bytes, :allowed_media_types, :after_connect_redirect
    attr_reader :auth_path

    def initialize
      @auth_path = (ENV["INSTAGRAM_CONNECT_AUTH_PATH"] || "instagram_login").to_sym
      @app_id = ENV["INSTAGRAM_CONNECT_APP_ID"] || ENV["INSTAGRAM_APP_ID"]
      @app_secret = ENV["INSTAGRAM_CONNECT_APP_SECRET"] || ENV["INSTAGRAM_APP_SECRET"]
      @verify_token = ENV["INSTAGRAM_CONNECT_VERIFY_TOKEN"] || ENV["INSTAGRAM_VERIFY_TOKEN"]
      @graph_version = ENV.fetch("INSTAGRAM_CONNECT_GRAPH_VERSION", "v21.0")
      @redirect_uri = ENV["INSTAGRAM_CONNECT_REDIRECT_URI"]
      @encrypt_tokens = true
      @parent_controller = "::ApplicationController"
      @authenticate_with = nil
      @current_user_id_resolver = -> { respond_to?(:current_user) && current_user ? current_user.id : nil }
      @on_message = nil
      @on_comment = nil
      @on_postback = nil
      @logger = Logger.new($stdout)
      @default_per_page = 25
      @inherit_host_layout = true
      # Where the OAuth callback redirects after connecting an account.
      @after_connect_redirect = "/"
      @media_max_bytes = 25 * 1024 * 1024
      @allowed_media_types = %w[
        image/jpeg image/png image/gif image/webp
        video/mp4 audio/mpeg audio/aac application/pdf
      ].freeze
    end

    # Coerce to a symbol so hosts may pass a string ("facebook_login") from a
    # config hash or ENV.
    def auth_path=(value)
      @auth_path = value&.to_sym
    end

    # Called by .configure at boot. Validates only structural config (a known
    # auth_path) so an unconfigured host can still boot; secret presence is
    # enforced lazily at the point of use (Client / OAuth).
    def validate!
      unless AUTH_PATHS.include?(auth_path)
        raise ConfigurationError,
          "auth_path must be one of #{AUTH_PATHS.join(', ')} (got #{auth_path.inspect})"
      end
      true
    end
  end
end

require "logger"
require_relative "instagram_connect/version"
require_relative "instagram_connect/errors"
require_relative "instagram_connect/result"
require_relative "instagram_connect/configuration"
require_relative "instagram_connect/auth/strategy"
require_relative "instagram_connect/auth/instagram_login"
require_relative "instagram_connect/auth/facebook_login"
require_relative "instagram_connect/auth"
require_relative "instagram_connect/client"
require_relative "instagram_connect/connect"

# InstagramConnect connects a Rails app to Instagram over the official Meta
# Graph API: receive and reply to DMs and comments in real time via
# HMAC-verified webhooks, publish posts, and manage OAuth tokens.
#
#   InstagramConnect.configure do |c|
#     c.auth_path   = :facebook_login
#     c.app_id      = Rails.application.credentials.dig(:instagram_connect, :app_id)
#     c.app_secret  = Rails.application.credentials.dig(:instagram_connect, :app_secret)
#     c.verify_token = Rails.application.credentials.dig(:instagram_connect, :verify_token)
#   end
module InstagramConnect
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    attr_writer :configuration

    def configure
      yield(configuration)
      configuration.validate!
      configuration
    end

    def reset!
      @configuration = Configuration.new
    end
  end
end

# :nocov:
if defined?(Rails::Engine)
  require_relative "instagram_connect/engine"
elsif defined?(Rails::Railtie)
  require_relative "instagram_connect/railtie"
end
# :nocov:

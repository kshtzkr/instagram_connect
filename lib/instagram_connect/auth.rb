module InstagramConnect
  # Selects the auth strategy for the configured path. New login paths register
  # by adding a class to STRATEGIES — the same config-symbol dispatch used
  # across the house gems.
  module Auth
    STRATEGIES = {
      instagram_login: InstagramLogin,
      facebook_login: FacebookLogin
    }.freeze

    def self.for(config)
      klass = STRATEGIES[config.auth_path]
      raise ConfigurationError, "unknown auth_path #{config.auth_path.inspect}" unless klass
      klass.new(config)
    end
  end
end

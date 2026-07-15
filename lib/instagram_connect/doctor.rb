module InstagramConnect
  # Preflight configuration checks, surfaced by the `instagram_connect doctor`
  # CLI. Returns a list of { label:, ok: } so the CLI (or a host) can render it.
  class Doctor
    def self.run(config: InstagramConnect.configuration)
      [
        check("auth_path is valid", Configuration::AUTH_PATHS.include?(config.auth_path)),
        check("app_id is set", present?(config.app_id)),
        check("app_secret is set", present?(config.app_secret)),
        check("verify_token is set", present?(config.verify_token))
      ]
    end

    def self.check(label, ok)
      { label: label, ok: ok }
    end

    def self.present?(value)
      !value.to_s.empty?
    end
  end
end

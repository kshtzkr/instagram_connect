require "rails/engine"

module InstagramConnect
  # Mountable, namespace-isolated engine. Unlike whatsapp_notifier, the module
  # name "InstagramConnect" is the Zeitwerk default camelization of
  # "instagram_connect", so no inflector override is needed.
  class Engine < ::Rails::Engine
    isolate_namespace InstagramConnect

    config.instagram_connect = {}

    # Keep tokens and secrets out of logs.
    initializer "instagram_connect.filter_sensitive_params" do |app|
      app.config.filter_parameters += %i[access_token app_secret verify_token hub_verify_token]
    end

    # Ship migrations inside the gem and run them in place — the host just runs
    # `rails db:migrate`, no copying. The gem owns the data model, so every
    # adopter gets exactly the same schema, versioned with the gem.
    initializer "instagram_connect.append_migrations" do |app|
      unless app.root.to_s == root.to_s
        config.paths["db/migrate"].expanded.each do |expanded_path|
          app.config.paths["db/migrate"] << expanded_path
        end
      end
    end

    # Apply any host-provided config.instagram_connect = { ... } hash onto the
    # gem Configuration via setters (in addition to the initializer DSL).
    initializer "instagram_connect.configure" do |app|
      InstagramConnect.configure do |config|
        app.config.instagram_connect.each do |key, value|
          setter = "#{key}="
          config.public_send(setter, value) if config.respond_to?(setter)
        end
      end
    end

    # Enable at-rest token encryption on boot (and re-apply on each dev reload,
    # since the Account class is reloaded fresh). Without this the `encrypts`
    # decoration never runs in a host app and access tokens persist in plain
    # text. Opt out with `config.encrypt_tokens = false` (e.g. no Active Record
    # Encryption configured).
    config.to_prepare do
      InstagramConnect::Account.enable_token_encryption! if InstagramConnect.configuration.encrypt_tokens
    end
  end
end

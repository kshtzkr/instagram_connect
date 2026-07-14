require "rails/railtie"

module InstagramConnect
  # Loaded when Rails is present but the full Engine is not (e.g. a bare Rails
  # app that only wants the client, not the mounted UI). Mirrors the engine's
  # configure initializer.
  class Railtie < ::Rails::Railtie
    config.instagram_connect = {}

    initializer "instagram_connect.configure" do |app|
      InstagramConnect.configure do |config|
        app.config.instagram_connect.each do |key, value|
          setter = "#{key}="
          config.public_send(setter, value) if config.respond_to?(setter)
        end
      end
    end
  end
end

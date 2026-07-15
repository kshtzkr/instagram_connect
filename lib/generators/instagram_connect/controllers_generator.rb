require "rails/generators"

module InstagramConnect
  module Generators
    # `rails g instagram_connect:controllers` — copy the engine's controllers
    # into the host app for deeper customization. Overridden controllers take
    # precedence over the engine's.
    class ControllersGenerator < ::Rails::Generators::Base
      source_root InstagramConnect::Engine.root.join("app/controllers").to_s

      def copy_controllers
        directory "instagram_connect", "app/controllers/instagram_connect"
      end
    end
  end
end

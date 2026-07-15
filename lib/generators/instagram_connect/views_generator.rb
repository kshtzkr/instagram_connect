require "rails/generators"

module InstagramConnect
  module Generators
    # `rails g instagram_connect:views` — copy the engine's views into the host
    # app so they can be restyled to the app's own design system.
    class ViewsGenerator < ::Rails::Generators::Base
      source_root InstagramConnect::Engine.root.join("app/views").to_s

      def copy_views
        directory "instagram_connect", "app/views/instagram_connect"
        directory "layouts/instagram_connect", "app/views/layouts/instagram_connect"
      end
    end
  end
end

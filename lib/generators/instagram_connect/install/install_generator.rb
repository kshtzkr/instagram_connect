require "rails/generators"

module InstagramConnect
  module Generators
    # `rails g instagram_connect:install` — writes the initializer and mounts the
    # engine. Migrations ship inside the gem and run in place (just
    # `rails db:migrate`), so there is nothing to copy.
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_initializer
        template "instagram_connect.rb.tt", "config/initializers/instagram_connect.rb"
      end

      def mount_engine
        route %(mount InstagramConnect::Engine => "/instagram")
      end

      def show_readme
        say "\ninstagram_connect installed. Next:"
        say "  bin/rails db:migrate   # runs the engine's migrations in place"
        say "  Configure config/initializers/instagram_connect.rb, then mount is at /instagram\n"
      end
    end
  end
end

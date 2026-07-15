require "rails/generators"
require "rails/generators/active_record"

module InstagramConnect
  module Generators
    # `rails g instagram_connect:install` — writes the initializer, mounts the
    # engine at /instagram, and copies the database migrations.
    class InstallGenerator < ::Rails::Generators::Base
      include ::Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      MIGRATIONS = %w[
        create_instagram_connect_accounts
        create_instagram_connect_conversations
        create_instagram_connect_messages
        create_instagram_connect_inbound_messages
        create_instagram_connect_comments
      ].freeze

      def self.next_migration_number(dirname)
        ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def create_initializer
        template "instagram_connect.rb.tt", "config/initializers/instagram_connect.rb"
      end

      def mount_engine
        route %(mount InstagramConnect::Engine => "/instagram")
      end

      def copy_migrations
        MIGRATIONS.each do |name|
          migration_template "#{name}.rb.tt", "db/migrate/#{name}.rb"
        end
      end
    end
  end
end

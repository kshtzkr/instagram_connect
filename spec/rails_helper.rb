require_relative "spec_helper"

# Boot the dummy application exactly once, even if this file is evaluated more
# than once (Rails::Application#initialize! raises on a second call).
return if defined?(INSTAGRAM_CONNECT_TEST_BOOTED)
INSTAGRAM_CONNECT_TEST_BOOTED = true

ENV["RAILS_ENV"] ||= "test"

require "rails"
require "action_controller/railtie"
require "active_record"
require "active_job"
require "rspec/rails"
require "instagram_connect"
require "fileutils"
require "yaml"

# INSTAGRAM_CONNECT_TEST_DATABASE_URL switches the suite onto a real database
# (CI runs it against Postgres). Unset, it is in-memory SQLite so a contributor
# needs no services.
INSTAGRAM_CONNECT_TEST_DATABASE =
  if (url = ENV["INSTAGRAM_CONNECT_TEST_DATABASE_URL"].presence)
    { "url" => url }
  else
    { "adapter" => "sqlite3", "database" => ":memory:" }
  end

# The dummy app gets its own root under tmp/ rather than borrowing the gem's.
# Sharing the gem's root meant the app tried to load the gem's own
# config/routes.rb as its application routes, double-drawing the engine; and
# Active Storage's engine loads the Active Record railtie, which insists on a
# real config/database.yml even for an app that connects by hand. A throwaway
# root gives both of them what they expect and is closer to a real host.
INSTAGRAM_CONNECT_DUMMY_ROOT = File.expand_path("../tmp/dummy", __dir__)
FileUtils.mkdir_p(File.join(INSTAGRAM_CONNECT_DUMMY_ROOT, "config"))
File.write(
  File.join(INSTAGRAM_CONNECT_DUMMY_ROOT, "config", "database.yml"),
  YAML.dump("test" => INSTAGRAM_CONNECT_TEST_DATABASE)
)

require "active_storage/engine"

# Configure the gem before any model with `encrypts` autoloads.
InstagramConnect.configure do |c|
  c.auth_path = :instagram_login
  c.app_id = "APPID"
  c.app_secret = "SECRET"
  c.verify_token = "VERIFY"
end

# A minimal host application that mounts the engine. Active Record is used bare
# (manual in-memory connection) rather than via its railtie, so there is no
# database.yml to manage.
module Dummy
  class Application < Rails::Application
    config.eager_load = false
    config.secret_key_base = "instagram_connect_dummy_secret_key_base_000000000000"
    config.hosts.clear
    config.logger = Logger.new(IO::NULL)
    config.cache_store = :null_store
    config.instagram_connect = {}
    config.root = INSTAGRAM_CONNECT_DUMMY_ROOT
    # Set through the railtie rather than by calling
    # ActiveRecord::Encryption.configure directly: with Active Record's railtie
    # loaded (Active Storage pulls it in), the railtie re-reads these during
    # initialisation and would overwrite a manual call. Mirrors a host that has
    # run bin/rails db:encryption:init.
    config.active_record.encryption.primary_key = "test_primary_key_padding_1234567890"
    config.active_record.encryption.deterministic_key = "test_deterministic_key_padding_1234567890"
    config.active_record.encryption.key_derivation_salt = "test_key_derivation_salt_padding_1234567890"
    # Routes are drawn manually below.
    config.paths["config/routes.rb"] = []
    # Active Storage is optional for adopters but exercised here, because the
    # inbound media path is the one most likely to break quietly.
    config.active_storage.service = :test
    config.active_storage.service_configurations = {
      "test" => { "service" => "Disk", "root" => File.expand_path("../tmp/storage", __dir__) }
    }
  end
end

Dummy::Application.initialize!

Dummy::Application.routes.draw do
  mount InstagramConnect::Engine => "/instagram"
  root to: ->(_env) { [ 200, { "Content-Type" => "text/plain" }, [ "ok" ] ] }
end

# Host base controller referenced by the default parent_controller.
class ApplicationController < ActionController::Base
end

# The schema comes from the gem's own db/migrate — the same files a host app
# runs. A hand-maintained duplicate here would drift, and worse, it would hide
# adapter-specific DDL bugs: the migrations would never actually execute in CI,
# so a Postgres-only construct would only surface in an adopter's deploy.
ActiveRecord::Base.establish_connection(INSTAGRAM_CONNECT_TEST_DATABASE.symbolize_keys)
ActiveRecord::Migration.verbose = false
INSTAGRAM_CONNECT_MIGRATION_PATH = File.expand_path("../db/migrate", __dir__)
# Active Storage's own tables come from its engine, exactly as they would in a
# host that ran `bin/rails active_storage:install`.
ActiveRecord::MigrationContext.new(
  [ INSTAGRAM_CONNECT_MIGRATION_PATH, ActiveStorage::Engine.root.join("db/migrate").to_s ]
).migrate

# Note: token encryption is enabled by the engine's to_prepare hook during
# Dummy::Application.initialize! above — no manual call needed here.

ActiveJob::Base.queue_adapter = :test

RSpec.configure do |config|
  config.include ActiveJob::TestHelper
  config.use_transactional_fixtures = false if config.respond_to?(:use_transactional_fixtures=)

  # Re-apply a known gem configuration each example (the global spec_helper
  # after-hook resets it) and clear the tables. Examples do not run in a
  # transaction, so this is what keeps them isolated — and on a real database
  # it is what stops one example's rows leaking into the next.
  config.before do
    InstagramConnect.configure do |c|
      c.auth_path = :instagram_login
      c.app_id = "APPID"
      c.app_secret = "SECRET"
      c.verify_token = "VERIFY"
      c.inherit_host_layout = false
    end

    # Child-first so a foreign key (if an adopter's database enforces one)
    # never blocks the delete.
    InstagramConnect::WebhookEvent.delete_all
    InstagramConnect::MessageReaction.delete_all
    InstagramConnect::MessageAttachment.delete_all
    InstagramConnect::Mention.delete_all
    InstagramConnect::InsightSnapshot.delete_all
    InstagramConnect::MediaItem.delete_all
    InstagramConnect::Message.delete_all
    InstagramConnect::Conversation.delete_all
    InstagramConnect::Comment.delete_all
    InstagramConnect::InboundMessage.delete_all
    InstagramConnect::Account.delete_all

    if ActiveJob::Base.queue_adapter.respond_to?(:enqueued_jobs)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      ActiveJob::Base.queue_adapter.performed_jobs.clear
    end
  end
end

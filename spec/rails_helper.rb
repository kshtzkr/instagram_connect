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
    # The dummy app's root is the gem dir, so without this it would load the
    # gem's own config/routes.rb as its app routes (double-drawing the engine
    # routes and colliding on named routes). Routes are drawn manually below.
    config.paths["config/routes.rb"] = []
  end
end

# Configure AR encryption before initialize! so the engine's to_prepare hook can
# enable `encrypts` on the Account model at boot (mirrors a real host that has
# run `bin/rails db:encryption:init`).
ActiveRecord::Encryption.configure(
  primary_key: "test_primary_key_padding_1234567890",
  deterministic_key: "test_deterministic_key_padding_1234567890",
  key_derivation_salt: "test_key_derivation_salt_padding_1234567890"
)

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
#
# INSTAGRAM_CONNECT_TEST_DATABASE_URL switches the suite onto a real database
# (CI runs it against Postgres). Unset, it is in-memory SQLite so a contributor
# needs no services.
ActiveRecord::Base.establish_connection(
  ENV["INSTAGRAM_CONNECT_TEST_DATABASE_URL"].presence || { adapter: "sqlite3", database: ":memory:" }
)
ActiveRecord::Migration.verbose = false
INSTAGRAM_CONNECT_MIGRATION_PATH = File.expand_path("../db/migrate", __dir__)
ActiveRecord::MigrationContext.new(INSTAGRAM_CONNECT_MIGRATION_PATH).migrate

# Note: token encryption is enabled by the engine's to_prepare hook during
# Dummy::Application.initialize! above — no manual call needed here.

ActiveJob::Base.queue_adapter = :test

RSpec.configure do |config|
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

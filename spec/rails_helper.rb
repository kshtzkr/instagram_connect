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

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :instagram_connect_accounts, force: true do |t|
    t.string :auth_path, null: false
    t.string :ig_user_id, null: false
    t.string :page_id
    t.string :username
    t.text :access_token
    t.datetime :token_expires_at
    t.boolean :active, default: true, null: false
    t.bigint :connected_by_id
    t.timestamps
  end
  add_index :instagram_connect_accounts, :ig_user_id, unique: true

  create_table :instagram_connect_conversations, force: true do |t|
    t.bigint :account_id, null: false
    t.string :igsid, null: false
    t.string :username
    t.string :display_name
    t.datetime :last_message_at
    t.datetime :last_inbound_at
    t.string :last_message_preview
    t.integer :unread_count, default: 0, null: false
    t.timestamps
  end
  add_index :instagram_connect_conversations, [ :account_id, :igsid ], unique: true

  create_table :instagram_connect_messages, force: true do |t|
    t.bigint :conversation_id, null: false
    t.string :direction, null: false
    t.string :status, null: false
    t.string :kind, default: "dm", null: false
    t.string :source
    t.text :body
    t.string :ig_message_id
    t.string :message_tag
    t.bigint :sent_by_id
    t.string :media_status, default: "none", null: false
    t.string :media_mime
    t.string :media_filename
    t.integer :media_size
    t.string :media_error
    t.string :error_message
    t.string :failure_reason
    t.timestamps
  end
  add_index :instagram_connect_messages, :ig_message_id, unique: true

  create_table :instagram_connect_inbound_messages, force: true do |t|
    t.string :ig_message_id, null: false
    t.bigint :account_id
    t.datetime :processed_at
    t.timestamps
  end
  add_index :instagram_connect_inbound_messages, :ig_message_id, unique: true

  create_table :instagram_connect_comments, force: true do |t|
    t.bigint :account_id, null: false
    t.string :media_id
    t.string :comment_id, null: false
    t.string :parent_id
    t.string :from_username
    t.text :text
    t.datetime :hidden_at
    t.datetime :replied_at
    t.timestamps
  end
  add_index :instagram_connect_comments, :comment_id, unique: true
end

# Note: token encryption is enabled by the engine's to_prepare hook during
# Dummy::Application.initialize! above — no manual call needed here.

ActiveJob::Base.queue_adapter = :test

RSpec.configure do |config|
  config.use_transactional_fixtures = false if config.respond_to?(:use_transactional_fixtures=)

  # Re-apply a known gem configuration each example (the global spec_helper
  # after-hook resets it) and clear the in-memory tables.
  config.before do
    InstagramConnect.configure do |c|
      c.auth_path = :instagram_login
      c.app_id = "APPID"
      c.app_secret = "SECRET"
      c.verify_token = "VERIFY"
      c.inherit_host_layout = false
    end

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

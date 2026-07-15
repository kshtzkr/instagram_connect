require_relative "spec_helper"

ENV["RAILS_ENV"] ||= "test"

require "bundler/setup"
require "active_record"
require "active_job"
require "instagram_connect"

# Active Record Encryption must be configured before any model that calls
# `encrypts` is exercised.
ActiveRecord::Encryption.configure(
  primary_key: "test_primary_key_padding_1234567890",
  deterministic_key: "test_deterministic_key_padding_1234567890",
  key_derivation_salt: "test_key_derivation_salt_padding_1234567890"
)

require_relative "../app/models/instagram_connect/application_record"
require_relative "../app/models/instagram_connect/account"
require_relative "../app/models/instagram_connect/conversation"
require_relative "../app/models/instagram_connect/message"
require_relative "../app/models/instagram_connect/inbound_message"
require_relative "../app/models/instagram_connect/comment"
require_relative "../app/jobs/instagram_connect/application_job"
require_relative "../app/jobs/instagram_connect/refresh_tokens_job"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

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

InstagramConnect::Account.enable_token_encryption!

ActiveJob::Base.queue_adapter = :test

RSpec.configure do |config|
  config.before do
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

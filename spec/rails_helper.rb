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
end

InstagramConnect::Account.enable_token_encryption!

ActiveJob::Base.queue_adapter = :test

RSpec.configure do |config|
  config.before do
    InstagramConnect::Account.delete_all
    if ActiveJob::Base.queue_adapter.respond_to?(:enqueued_jobs)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      ActiveJob::Base.queue_adapter.performed_jobs.clear
    end
  end
end

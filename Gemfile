source "https://rubygems.org"

# Specify your gem's dependencies in instagram_connect.gemspec.
gemspec

gem "puma"

gem "sqlite3"
# The suite runs on SQLite by default so a contributor needs no services, and on
# Postgres in CI so adapter-specific DDL in db/migrate cannot reach an adopter
# unnoticed. See INSTAGRAM_CONNECT_TEST_DATABASE_URL in spec/rails_helper.rb.
gem "pg"
gem "rack-test"
gem "webmock"
gem "rspec-rails", "~> 8.0"
gem "factory_bot"
gem "simplecov", require: false

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

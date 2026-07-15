require "rails_helper"

RSpec.describe "gem migrations" do
  migration_files = Dir[File.expand_path("../db/migrate/*.rb", __dir__)].sort

  it "ships one create migration per table, each with a real 14-digit timestamp" do
    expect(migration_files.size).to eq(5)
    migration_files.each do |file|
      expect(File.basename(file)).to match(/\A\d{14}_create_instagram_connect_\w+\.rb\z/)
    end
  end

  it "are idempotent — safe to run against a database that already has the tables" do
    # rails_helper already created every table via the inline schema, so running
    # each migration up must be a no-op (if_not_exists), not a DuplicateTable
    # error — the exact situation on a deploy whose DB already has the tables.
    was_verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false

    migration_files.each do |file|
      require file
      klass = File.basename(file, ".rb").sub(/\A\d+_/, "").camelize.constantize
      expect { klass.new.migrate(:up) }.not_to raise_error
    end
  ensure
    ActiveRecord::Migration.verbose = was_verbose
  end
end

require "rails_helper"

RSpec.describe "gem migrations" do
  migration_files = Dir[File.expand_path("../db/migrate/*.rb", __dir__)].sort

  it "ships at least one migration per table the gem owns" do
    expect(migration_files.size).to be >= InstagramConnect::TABLES.size
  end

  # The gem appends its migration path to the host's, so these filenames land in
  # the same ordering space as the host's own migrations. An invented version
  # (20240101...) sorts before a host migration written years later and silently
  # reorders that host's deploy.
  it "names every migration with a real 14-digit UTC timestamp" do
    migration_files.each do |file|
      basename = File.basename(file)
      expect(basename).to match(/\A\d{14}_[a-z0-9_]+\.rb\z/)

      version = basename[0, 14]
      stamped = Time.utc(version[0, 4], version[4, 2], version[6, 2],
                         version[8, 2], version[10, 2], version[12, 2])
      expect(stamped).to be > Time.utc(2020, 1, 1)
      expect(stamped).to be < Time.now.utc + 86_400
    end
  end

  it "keeps versions unique" do
    versions = migration_files.map { |file| File.basename(file)[0, 14] }
    expect(versions.uniq.size).to eq(versions.size)
  end

  it "creates every table the gem's models expect" do
    expect(ActiveRecord::Base.connection.tables).to include(*InstagramConnect::TABLES)
  end

  it "are idempotent — safe to re-run against a database that already has the tables" do
    # rails_helper migrated this database at boot, so running each migration up
    # again must be a no-op (every statement carries if_not_exists) rather than a
    # DuplicateTable error. That is the exact situation on a deploy whose database
    # already has the tables — the bug 0.2.1 shipped to fix.
    migration_files.each do |file|
      require file
      klass = File.basename(file, ".rb").sub(/\A\d+_/, "").camelize.constantize
      expect { klass.new.migrate(:up) }.not_to raise_error
    end
  end
end

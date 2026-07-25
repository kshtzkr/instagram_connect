require "spec_helper"

# The coverage gate is a denylist (spec/spec_helper.rb). A denylist has one
# failure mode an allowlist does not: rename or delete a filtered path and the
# filter silently starts matching nothing — or worse, a future file at the old
# path is excluded without anyone deciding that. This pins it.
RSpec.describe "coverage filters" do
  FILTERED_PATHS = %w[
    lib/instagram_connect/version.rb
    lib/generators
    lib/instagram_connect/engine.rb
    lib/instagram_connect/railtie.rb
    db/migrate
  ].freeze

  it "excludes only paths that still exist" do
    FILTERED_PATHS.each do |path|
      expect(File.exist?(File.expand_path("../#{path}", __dir__))).to be(true),
        "spec_helper filters #{path}, which no longer exists — drop the filter or fix the path"
    end
  end

  it "keeps the exclusion list small enough to stay deliberate" do
    # Not a style rule: every entry here is code nobody is required to test.
    # If this list is growing, the gate is quietly eroding.
    expect(FILTERED_PATHS.size).to be <= 6
  end
end

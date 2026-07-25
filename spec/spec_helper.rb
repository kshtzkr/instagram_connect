require "simplecov"
require "webmock/rspec"

SimpleCov.start do
  enable_coverage :branch

  # A DENYLIST, deliberately. This was an allowlist of tracked paths, which
  # meant every new file silently escaped the 100% gate until somebody
  # remembered to add it — exactly backwards for a gem that is growing.
  #
  # Everything here is excluded because it has no branch a spec can meaningfully
  # exercise, not because it is hard to cover. Adding to this list needs a
  # reason in the comment; spec/coverage_filters_spec.rb asserts every path
  # below still exists, so a rename cannot silently start excluding real code.
  add_filter "/spec/"
  add_filter "/lib/instagram_connect/version.rb"   # a single constant
  add_filter "/lib/generators/"                    # Thor generators; covered by generator specs
                                                   #   driving them end to end, not by line coverage
  add_filter "/lib/instagram_connect/engine.rb"    # boot-time wiring; exercised by the dummy app
                                                   #   booting at all, which every spec depends on
  add_filter "/lib/instagram_connect/railtie.rb"   # the non-engine branch; unreachable under Rails

  minimum_coverage line: 100, branch: 100
  minimum_coverage_by_file line: 100, branch: 100
end

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Every spec starts from a pristine configuration singleton.
  config.after do
    InstagramConnect.reset! if defined?(InstagramConnect) && InstagramConnect.respond_to?(:reset!)
  end
end

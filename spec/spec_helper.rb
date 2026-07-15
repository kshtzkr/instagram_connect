require "simplecov"
require "webmock/rspec"

SimpleCov.start do
  enable_coverage :branch

  # Enforce 100% on the gem's business-logic files. Framework glue (engine,
  # railtie, configuration defaults) and generated views/templates are excluded
  # from the gate, matching the house convention (see rails-contact). The list
  # grows as each build phase adds logic.
  tracked = %w[
    /lib/instagram_connect/result.rb
    /lib/instagram_connect/errors.rb
    /lib/instagram_connect/auth/strategy.rb
    /lib/instagram_connect/auth/instagram_login.rb
    /lib/instagram_connect/auth/facebook_login.rb
    /lib/instagram_connect/auth.rb
    /lib/instagram_connect/client.rb
    /lib/instagram_connect/connect.rb
    /app/models/instagram_connect/account.rb
    /app/jobs/instagram_connect/refresh_tokens_job.rb
  ]
  add_filter do |source_file|
    tracked.none? { |file| source_file.filename.end_with?(file) }
  end

  minimum_coverage 100
  minimum_coverage_by_file 100
  minimum_coverage branch: 100
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

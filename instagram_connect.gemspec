require_relative "lib/instagram_connect/version"

Gem::Specification.new do |spec|
  spec.name = "instagram_connect"
  spec.version = InstagramConnect::VERSION
  spec.authors = [ "Kshitiz Sinha" ]
  spec.email = [ "kshtzkr@gmail.com" ]
  spec.homepage = "https://github.com/kshtzkr/instagram_connect"
  spec.summary = "Instagram DMs, comments, and publishing for Rails via the official Meta Graph API."
  spec.description = "A mountable Rails engine that connects your app to Instagram: receive and reply to DMs and comments in real time over HMAC-verified webhooks, publish posts, and manage OAuth tokens — using the official Instagram Graph API (Instagram-Login or Facebook-Login), no unofficial automation."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/kshtzkr/instagram_connect/tree/main"
  spec.metadata["changelog_uri"] = "https://github.com/kshtzkr/instagram_connect/releases"
  spec.metadata["bug_tracker_uri"] = "https://github.com/kshtzkr/instagram_connect/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.glob("{app,bin,config,db,lib,docs,.github}/**/*") + %w[README.md CHANGELOG.md MIT-LICENSE LICENSE.txt Gemfile Rakefile .rspec]
  spec.bindir = "bin"
  spec.executables = [ "instagram_connect" ]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "rails", ">= 7.1"
  spec.add_dependency "httparty", ">= 0.21"
  spec.add_dependency "thor", ">= 1.0"
end

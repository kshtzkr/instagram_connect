require "thor"
require_relative "doctor"

module InstagramConnect
  # Command-line entry point: `bundle exec instagram_connect doctor`.
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "doctor", "Check the instagram_connect configuration"
    def doctor
      Doctor.run.each do |check|
        say(format("%-9s %s", check[:ok] ? "OK" : "MISSING", check[:label]))
      end
    end
  end
end

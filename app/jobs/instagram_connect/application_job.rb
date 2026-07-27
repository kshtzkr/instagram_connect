module InstagramConnect
  class ApplicationJob < ActiveJob::Base
    # A token this process cannot decrypt is a configuration fault, not a
    # transient one: retrying re-raises forever and Meta only ever answers
    # "Cannot parse access token". Log the actionable message once and stop —
    # Account#client has already stamped readiness_error for the health screen.
    rescue_from InstagramConnect::TokenUnreadableError do |error|
      logger.error("[instagram_connect] #{self.class.name} aborted: #{error.message}")
    end
  end
end

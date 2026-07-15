module InstagramConnect
  # Refreshes access tokens for active accounts before they expire. Schedule it
  # daily (e.g. via Solid Queue recurring tasks). One account's failure never
  # aborts the batch. Accounts on a non-expiring path (Facebook-Login) simply
  # keep their token — refresh_token there is a no-op.
  class RefreshTokensJob < ApplicationJob
    queue_as :default

    DEFAULT_WINDOW = 7 * 24 * 60 * 60 # seconds

    def perform(within: DEFAULT_WINDOW)
      threshold = Time.current + within
      Account.active.token_expiring_before(threshold).find_each do |account|
        account.refresh_access_token!
      rescue StandardError => e
        InstagramConnect.configuration.logger&.error(
          "[instagram_connect] token refresh failed for account #{account.id}: #{e.message}"
        )
      end
    end
  end
end

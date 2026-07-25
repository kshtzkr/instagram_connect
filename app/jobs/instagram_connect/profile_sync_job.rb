module InstagramConnect
  # Fills in who people actually are.
  #
  # The columns for this have existed since 0.1 and nothing ever wrote them, so
  # an inbox showed a 17-digit Instagram-scoped id where a handle belongs and an
  # account showed nothing at all. Meta returns profile data on a separate call
  # from the message, so it has to be fetched deliberately.
  #
  # Re-syncing is rate-limited by RESYNC_AFTER rather than by cleverness: a
  # display name changes rarely, and every refetch spends budget that inbound
  # message handling needs more.
  class ProfileSyncJob < ApplicationJob
    queue_as :default

    RESYNC_AFTER = 7.days

    def perform(account_id: nil, conversation_id: nil)
      if conversation_id
        sync_conversation(Conversation.find_by(id: conversation_id))
      elsif account_id
        sync_account(Account.find_by(id: account_id))
      else
        Account.active.find_each { |account| sync_account(account) }
      end
    end

    private

    def sync_account(account)
      return if account.nil? || fresh?(account.profile_synced_at)

      result = account.client.account_profile
      return record_failure(account, result) unless result.success?

      data = result.data
      account.update!(
        username: data["username"].presence || account.username,
        name: data["name"].presence || account.name,
        profile_picture_url: data["profile_picture_url"],
        followers_count: data["followers_count"],
        media_count: data["media_count"],
        profile_synced_at: Time.current
      )
    end

    def sync_conversation(conversation)
      return if conversation.nil? || fresh?(conversation.profile_synced_at)

      result = conversation.account.client.profile(igsid: conversation.igsid)

      # A customer who blocked the business, or deleted their account, cannot be
      # looked up. Stamping the attempt stops the job retrying them on every
      # message they ever sent.
      unless result.success?
        conversation.update_columns(profile_synced_at: Time.current)
        return
      end

      data = result.data
      conversation.update!(
        username: data["username"].presence || conversation.username,
        display_name: data["name"].presence || conversation.display_name,
        profile_picture_url: data["profile_pic"] || data["profile_picture_url"],
        profile_synced_at: Time.current
      )
    end

    def fresh?(synced_at)
      synced_at.present? && synced_at > RESYNC_AFTER.ago
    end

    def record_failure(account, result)
      InstagramConnect.configuration.logger&.warn(
        "[InstagramConnect] profile sync failed for account=#{account.id}: #{result.error_message}"
      )
    end
  end
end

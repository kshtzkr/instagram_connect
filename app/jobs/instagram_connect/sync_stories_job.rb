module InstagramConnect
  # Mirrors the account's stories. Meta's /stories edge returns only the
  # stories still inside their 24 hours, and sends no webhook when one
  # expires — so this walk upserts what it sees and marks nothing: a story
  # that stops appearing has simply expired, which the row's posted_at
  # already tells the host. Expired stories keep their rows forever, same
  # never-delete rule as posts; their CDN URLs die with the story.
  #
  # Safe to re-run: MediaItem.record upserts on (account, ig_media_id).
  class SyncStoriesJob < ApplicationJob
    queue_as :default

    # Hosts enqueue this from screens; the cache key stops a busy screen
    # enqueueing it once per page view.
    THROTTLE = 10.minutes

    def self.enqueue_throttled(account)
      Rails.cache.fetch("instagram_connect:sync_stories:#{account.id}", expires_in: THROTTLE) do
        perform_later(account.id)
        true
      end
    end

    def perform(account_id)
      account = Account.find_by(id: account_id)
      return if account.nil? || !account.active?

      result = account.client.list_stories
      unless result.success?
        return logger.error("[instagram_connect] stories sync failed for " \
                            "account=#{account.id}: #{result.error_message}")
      end

      Array(result.data["data"]).each { |item| upsert(account, item) }
    end

    private

    def upsert(account, item)
      MediaItem.record(
        account: account,
        ig_media_id: item["id"],
        media_type: item["media_type"],
        media_product_type: item["media_product_type"] || "STORY",
        caption: item["caption"],
        permalink: item["permalink"],
        media_url: item["media_url"],
        thumbnail_url: item["thumbnail_url"],
        posted_at: parse_time(item["timestamp"]),
        synced_at: Time.current
      )
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

module InstagramConnect
  # Mirrors the account's posts — every post, from any app, not just ones
  # published through this gem.
  #
  # The comments webhook names only a media id, so without this a host shows
  # conversations grouped under bare 17-digit numbers. And Instagram sends no
  # webhook when a post is deleted, so absence from the account's own COMPLETED
  # listing is the only deletion signal there is: a vanished post is stamped
  # removed_from_instagram_at, never destroyed. A partial or failed walk marks
  # nothing — absence from an incomplete listing proves nothing.
  #
  # Safe to re-run: MediaItem.record upserts on (account, ig_media_id).
  class SyncMediaJob < ApplicationJob
    queue_as :default

    # Hosts enqueue this from screens; the cache key stops a busy inbox
    # enqueueing it once per page view.
    THROTTLE = 10.minutes

    # like_count and comments_count come straight off the media node — no
    # insights permission needed for the account's own posts. thumbnail_url is
    # the poster frame for videos, whose media_url is a playable mp4.
    MEDIA_FIELDS = "id,caption,media_type,media_url,thumbnail_url,permalink," \
                   "timestamp,like_count,comments_count".freeze

    def self.enqueue_throttled(account)
      Rails.cache.fetch("instagram_connect:sync_media:#{account.id}", expires_in: THROTTLE) do
        perform_later(account.id)
        true
      end
    end

    # full: walks the entire history with cursors and, having seen it all,
    # marks the known posts the listing no longer contains.
    def perform(account_id, full: false)
      account = Account.find_by(id: account_id)
      return if account.nil? || !account.active?

      started_at = Time.current
      result = fetch(account, full: full)
      unless result.success?
        # A sync that fails must say so — the silent version of this class of
        # job has already cost a production afternoon.
        return logger.error("[instagram_connect] media sync failed for " \
                            "account=#{account.id}: #{result.error_message}")
      end

      Array(result.data["data"]).each { |item| upsert(account, item) }
      mark_removed(account, started_at) if full
    end

    private

    def fetch(account, full:)
      return account.client.list_media unless full

      account.client.collect("/#{account.ig_user_id}/media",
                             { fields: MEDIA_FIELDS, limit: 25 })
    end

    def upsert(account, item)
      media = MediaItem.record(
        account: account,
        ig_media_id: item["id"],
        media_type: item["media_type"],
        caption: item["caption"],
        permalink: item["permalink"],
        media_url: item["media_url"],
        thumbnail_url: item["thumbnail_url"],
        like_count: item["like_count"],
        comments_count: item["comments_count"],
        posted_at: parse_time(item["timestamp"]),
        synced_at: Time.current
      )
      # Explicit, because record compacts nils out of its attributes: a post
      # that reappears in the listing un-grays.
      media.update!(removed_from_instagram_at: nil) if media.removed_from_instagram_at
    end

    def mark_removed(account, started_at)
      marked = MediaItem.where(account_id: account.id, removed_from_instagram_at: nil)
                        .where(synced_at: ...started_at)
                        .update_all(removed_from_instagram_at: Time.current)
      return unless marked.positive?

      logger.info("[instagram_connect] #{marked} post(s) newly absent from " \
                  "Instagram for account=#{account.id}")
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

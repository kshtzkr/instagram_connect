module InstagramConnect
  # Imports a post's existing comments — the ones that happened before the
  # webhook subscription existed, which the webhook can never deliver. The
  # comments edge is walked with cursors, replies expanded inline, and every
  # comment upserted by Meta's id, so re-running never duplicates and a
  # webhook-created row is simply enriched.
  #
  # Meta is the source of truth for hidden: a comment hidden from the app on
  # the phone arrives hidden here, and one unhidden there un-hides here.
  class SyncCommentsJob < ApplicationJob
    queue_as :default

    THROTTLE = 10.minutes

    REPLY_FIELDS = "id,text,timestamp,username,from,parent_id,hidden,like_count".freeze
    COMMENT_FIELDS = "#{REPLY_FIELDS},replies{#{REPLY_FIELDS}}".freeze

    # One key per post: opening a busy post's comments repeatedly enqueues one
    # import, not one per page view.
    def self.enqueue_throttled(account, ig_media_id)
      Rails.cache.fetch("instagram_connect:sync_comments:#{account.id}:#{ig_media_id}",
                        expires_in: THROTTLE) do
        perform_later(account.id, ig_media_id.to_s)
        true
      end
    end

    def perform(account_id, ig_media_id)
      account = Account.find_by(id: account_id)
      return if account.nil? || !account.active?

      result = account.client.collect("/#{ig_media_id}/comments",
                                      { fields: COMMENT_FIELDS, limit: 50 })
      unless result.success?
        return logger.error("[instagram_connect] comment sync failed for " \
                            "account=#{account.id} media=#{ig_media_id}: #{result.error_message}")
      end

      Array(result.data["data"]).each do |item|
        upsert(account, ig_media_id, item)
        Array(item.dig("replies", "data")).each do |reply|
          # Meta omits parent_id inside the replies expansion — the nesting
          # itself is the statement.
          upsert(account, ig_media_id, reply.merge("parent_id" => reply["parent_id"] || item["id"]))
        end
      end
    end

    private

    def upsert(account, ig_media_id, item)
      comment = Comment.record(
        account: account,
        comment_id: item["id"],
        media_id: ig_media_id.to_s,
        text: item["text"],
        from_username: item["username"] || item.dig("from", "username"),
        parent_id: item["parent_id"]
      )
      comment.update!(
        from_ig_id: item.dig("from", "id") || comment.from_ig_id,
        commented_at: parse_time(item["timestamp"]) || comment.commented_at,
        like_count: item["like_count"],
        hidden_at: item["hidden"] ? (comment.hidden_at || Time.current) : nil
      )
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

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

    # Only fields Meta documents for INSTAGRAM comments. from{...} and
    # parent_id are Facebook-comment fields; asking for them can fail the
    # whole call with (#100) — and one refused field means zero comments
    # imported. Reply nesting is derived from the replies expansion itself,
    # and the commenter's igsid still arrives via webhooks.
    REPLY_FIELDS = "id,text,timestamp,username,hidden,like_count".freeze
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
        import_replies(account, ig_media_id, item)
      end
    end

    private

    # The replies{} expansion is a single nested page. A comment whose thread
    # runs past it gets its replies edge walked in full — Instagram threads
    # are two-level, so this is the whole conversation, not a rabbit hole.
    def import_replies(account, ig_media_id, item)
      inline = Array(item.dig("replies", "data"))
      inline.each do |reply|
        # Meta omits parent_id inside the replies expansion — the nesting
        # itself is the statement.
        upsert(account, ig_media_id, reply.merge("parent_id" => reply["parent_id"] || item["id"]))
      end
      return if item.dig("replies", "paging", "next").blank?

      walk = account.client.collect("/#{item['id']}/replies",
                                    { fields: REPLY_FIELDS, limit: 50 })
      unless walk.success?
        return logger.error("[instagram_connect] replies walk failed for "                             "comment=#{item['id']}: #{walk.error_message}")
      end

      Array(walk.data["data"]).each do |reply|
        upsert(account, ig_media_id, reply.merge("parent_id" => reply["parent_id"] || item["id"]))
      end
    end

    def upsert(account, ig_media_id, item)
      comment = Comment.record(
        account: account,
        comment_id: item["id"],
        media_id: ig_media_id.to_s,
        text: item["text"],
        from_username: item["username"] || item.dig("from", "username"),
        parent_id: item["parent_id"].presence
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

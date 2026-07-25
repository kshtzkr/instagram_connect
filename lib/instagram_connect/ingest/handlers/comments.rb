module InstagramConnect
  class Ingest
    module Handlers
      # A comment on the account's own media. Also covers `live_comments`,
      # which carry the same shape — the difference is that a private reply to
      # a live comment is only valid while the broadcast is running.
      class Comments < Base
        def self.dedupe_key(event)
          event.dig("value", "id").presence
        end

        def self.requires_dedupe_key?
          true
        end

        def call
          comment = InstagramConnect::Comment.record(
            account: account,
            comment_id: value["id"].to_s,
            media_id: value.dig("media", "id"),
            text: value["text"],
            from_username: value.dig("from", "username"),
            parent_id: value["parent_id"]
          )
          comment.update!(
            from_ig_id: value.dig("from", "id"),
            commented_at: commented_at,
            # A private reply to a live comment is only valid while the
            # broadcast is running, so which field delivered this decides
            # whether that action can be offered at all.
            is_live: envelope.field == "live_comments"
          )

          record_media(comment)
          notify(config.on_comment, comment)
          comment
        end

        private

        def value
          event["value"] || {}
        end

        def commented_at
          envelope.occurred_at || Time.current
        end

        # The comment names a media we may never have seen — it could predate
        # this install, or have been posted from a phone.
        def record_media(comment)
          return if comment.media_id.blank?

          InstagramConnect::MediaItem.record(account: account, ig_media_id: comment.media_id)
        end
      end
    end
  end
end

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
          notify(config.on_comment, comment)
          comment
        end

        private

        def value
          event["value"] || {}
        end
      end
    end
  end
end

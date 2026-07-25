module InstagramConnect
  class Ingest
    module Handlers
      # Someone @mentioned the account, in a comment or in a caption.
      #
      # Meta does not store these notifications and never re-delivers them, so
      # this handler is the single point at which the event either becomes a row
      # or ceases to exist. Nothing here is allowed to be best-effort.
      class Mentions < Base
        def self.dedupe_key(event)
          value = event["value"] || {}
          media = value["media_id"].presence
          return nil if media.nil?

          "#{media}:#{value['comment_id'].presence || 'caption'}"
        end

        def self.requires_dedupe_key?
          true
        end

        def call
          InstagramConnect::MediaItem.record(account: account, ig_media_id: value["media_id"])

          InstagramConnect::Mention.record(
            account: account,
            kind: value["comment_id"].present? ? "comment" : "caption",
            ig_media_id: value["media_id"],
            comment_id: value["comment_id"],
            text: value["text"],
            from_username: value.dig("from", "username"),
            mentioned_at: mentioned_at
          )
        end

        private

        def value
          event["value"] || {}
        end

        def mentioned_at
          envelope.occurred_at || Time.current
        end
      end
    end
  end
end

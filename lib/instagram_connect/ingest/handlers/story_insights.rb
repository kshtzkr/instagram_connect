module InstagramConnect
  class Ingest
    module Handlers
      # A story expired, and Meta sent its final metrics with the notification.
      #
      # This is the only durable capture path there is. Story insights are
      # retrievable from the API for 24 hours; after that the numbers do not
      # exist anywhere. So the snapshot is written here, inside ingest, rather
      # than handed to a job that might be delayed past the point of no return.
      class StoryInsights < Base
        def self.dedupe_key(event)
          event.dig("value", "media_id").presence
        end

        def self.requires_dedupe_key?
          true
        end

        def call
          # The story may well have been posted from a phone rather than through
          # this app, so its media row might not exist yet.
          InstagramConnect::MediaItem.record(
            account: account, ig_media_id: media_id, media_product_type: "STORY"
          )

          InstagramConnect::InsightSnapshot.record(
            account: account,
            subject_type: "story",
            subject_ref: media_id,
            period: "lifetime",
            period_start: captured_at.to_date,
            source: "webhook",
            metrics: metrics,
            empty: metrics.empty?,
            captured_at: captured_at
          )
        end

        private

        def value
          event["value"] || {}
        end

        def media_id
          value["media_id"].to_s
        end

        # Everything except the identifier is a metric. Meta omits a metric it
        # will not report rather than sending a zero, and that distinction is
        # preserved by copying the payload as-is instead of filling defaults.
        def metrics
          @metrics ||= value.except("media_id")
        end

        def captured_at
          envelope.occurred_at || Time.current
        end
      end
    end
  end
end

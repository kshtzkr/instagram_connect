module InstagramConnect
  # A post, reel or story on the connected account — "IG Media" in Meta's
  # vocabulary. Named MediaItem because InstagramConnect::Media is already the
  # namespace for inbound file handling (Media::Limits, Media::Attaching); the
  # table keeps Meta's noun.
  class MediaItem < ApplicationRecord
    self.table_name = "instagram_connect_media"

    PRODUCT_TYPES = %w[FEED STORY REELS AD].freeze

    belongs_to :account, class_name: "InstagramConnect::Account"
    has_many :insight_snapshots, -> { where(subject_type: "media") },
             class_name: "InstagramConnect::InsightSnapshot",
             foreign_key: :subject_ref, primary_key: :ig_media_id,
             dependent: :destroy, inverse_of: false

    validates :ig_media_id, presence: true, uniqueness: { scope: :account_id }

    scope :stories, -> { where(media_product_type: "STORY") }
    # Everything that belongs on a feed grid. NULL-safe on purpose: rows
    # synced before media_product_type was requested have nil there, and a
    # plain where.not would silently drop them.
    scope :posts, -> { where("media_product_type IS NULL OR media_product_type <> 'STORY'") }
    scope :recent, -> { order(Arel.sql("posted_at IS NULL, posted_at DESC")) }

    # Upserts by Meta's id. Media arrives from several directions — a webhook
    # about a comment, a story expiring, a sync — and whichever gets there first
    # should create the row without the others having to care.
    # Stamped by SyncMediaJob when a completed listing no longer contains this
    # post. Deleted on Instagram never means deleted here.
    def removed?
      removed_from_instagram_at.present?
    end

    def self.record(account:, ig_media_id:, **attributes)
      media = find_or_initialize_by(account_id: account.id, ig_media_id: ig_media_id.to_s)
      media.assign_attributes(attributes.compact)
      media.save!
      media
    rescue ActiveRecord::RecordNotUnique
      find_by!(account_id: account.id, ig_media_id: ig_media_id.to_s)
    end

    def story?
      media_product_type == "STORY"
    end
  end
end

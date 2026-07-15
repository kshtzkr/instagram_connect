module InstagramConnect
  # One message bubble in a DM thread (or a story reply mirrored as a DM).
  class Message < ApplicationRecord
    self.table_name = "instagram_connect_messages"

    DIRECTIONS = %w[inbound outbound].freeze
    STATUSES = %w[received pending sending sent failed].freeze
    KINDS = %w[dm story_reply reaction].freeze
    SOURCES = %w[inbound manual api operator_app].freeze
    MEDIA_STATUSES = %w[none pending downloadable attached unavailable].freeze
    PREVIEW_LIMIT = 140

    belongs_to :conversation, class_name: "InstagramConnect::Conversation"

    validates :direction, inclusion: { in: DIRECTIONS }
    validates :status, inclusion: { in: STATUSES }
    validates :kind, inclusion: { in: KINDS }

    scope :inbound, -> { where(direction: "inbound") }
    scope :outbound, -> { where(direction: "outbound") }
    scope :chronological, -> { order(:created_at, :id) }

    def inbound?
      direction == "inbound"
    end

    def outbound?
      direction == "outbound"
    end

    # Short summary used for the inbox row preview.
    def preview
      return body.to_s.truncate(PREVIEW_LIMIT) if body.present?
      "[#{kind}]"
    end
  end
end

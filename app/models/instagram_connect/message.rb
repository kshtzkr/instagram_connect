module InstagramConnect
  # One message bubble in a DM thread (or a story reply mirrored as a DM).
  class Message < ApplicationRecord
    self.table_name = "instagram_connect_messages"

    DIRECTIONS = %w[inbound outbound].freeze
    STATUSES = %w[received pending sending sent failed].freeze
    KINDS = %w[dm story_reply story_mention reaction postback share unsupported].freeze
    SOURCES = %w[inbound manual api operator_app].freeze
    MEDIA_STATUSES = %w[none pending downloadable attached unavailable].freeze
    PREVIEW_LIMIT = 140

    belongs_to :conversation, class_name: "InstagramConnect::Conversation"
    # Denormalized from the conversation so account-scoped queries and stream
    # names do not need a join, and so uniqueness can be scoped per account.
    before_validation :inherit_account_id

    has_many :attachments, -> { order(:position) },
             class_name: "InstagramConnect::MessageAttachment",
             foreign_key: :message_id, dependent: :destroy
    has_many :reactions, class_name: "InstagramConnect::MessageReaction",
             foreign_key: :message_id, dependent: :nullify

    validates :direction, inclusion: { in: DIRECTIONS }
    validates :status, inclusion: { in: STATUSES }
    validates :kind, inclusion: { in: KINDS }

    scope :inbound, -> { where(direction: "inbound") }
    scope :outbound, -> { where(direction: "outbound") }
    # Ordered by Meta's clock, falling back to ours for rows written before
    # sent_at existed. A webhook batch delayed by a redeploy would otherwise
    # reorder the thread.
    scope :chronological, -> { order(Arel.sql("COALESCE(sent_at, created_at)"), :id) }

    # Extension point: a host rendering this record live overrides it to
    # re-broadcast current state after a callback-free write (update_all, which
    # the send and media paths both use to stay atomic). A no-op here keeps the
    # gem free of any Turbo dependency.
    def broadcast_refresh; end

    def occurred_at
      sent_at || created_at
    end

    def deleted?
      deleted_at.present?
    end

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

    private

    def inherit_account_id
      self.account_id ||= conversation&.account_id
    end
  end
end

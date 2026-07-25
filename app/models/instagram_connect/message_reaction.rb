module InstagramConnect
  # One reaction event on a message. Append-only — see the migration for why
  # current state is a read rather than a column.
  class MessageReaction < ApplicationRecord
    self.table_name = "instagram_connect_message_reactions"

    ACTIONS = %w[react unreact].freeze
    ACTORS = %w[customer business].freeze

    belongs_to :conversation, class_name: "InstagramConnect::Conversation"
    belongs_to :message, class_name: "InstagramConnect::Message", optional: true

    validates :ig_message_id, :igsid, :reacted_at, presence: true
    validates :action, inclusion: { in: ACTIONS }
    validates :actor, inclusion: { in: ACTORS }

    scope :chronological, -> { order(:reacted_at, :id) }

    # The reaction currently showing on a message, or nil if the last event was
    # an unreact. Reading MAX(reacted_at) rather than trusting arrival order is
    # what makes out-of-order delivery harmless.
    def self.current_for(ig_message_id)
      latest = where(ig_message_id: ig_message_id).chronological.last
      return nil if latest.nil? || latest.action == "unreact"

      latest
    end

    def react?
      action == "react"
    end
  end
end

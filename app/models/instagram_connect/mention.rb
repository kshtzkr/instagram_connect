module InstagramConnect
  # An @mention of the account, in a comment, a caption or a tag.
  #
  # Meta does not store these notifications and will not resend them, so this
  # table is the only record that a mention ever happened.
  class Mention < ApplicationRecord
    self.table_name = "instagram_connect_mentions"

    KINDS = %w[comment caption tag story].freeze

    belongs_to :account, class_name: "InstagramConnect::Account"
    belongs_to :message, class_name: "InstagramConnect::Message", optional: true

    validates :kind, inclusion: { in: KINDS }
    validates :mentioned_at, presence: true

    scope :unanswered, -> { where(replied_at: nil) }
    scope :recent, -> { order(mentioned_at: :desc) }

    def self.record(account:, kind:, mentioned_at:, ig_media_id: nil, comment_id: nil, **attributes)
      mention = find_or_initialize_by(
        account_id: account.id, kind: kind,
        ig_media_id: ig_media_id.presence, comment_id: comment_id.presence
      )
      mention.assign_attributes(attributes.compact.merge(mentioned_at: mentioned_at))
      mention.save!
      mention
    rescue ActiveRecord::RecordNotUnique
      find_by!(account_id: account.id, kind: kind,
               ig_media_id: ig_media_id.presence, comment_id: comment_id.presence)
    end

    def answered?
      replied_at.present?
    end
  end
end

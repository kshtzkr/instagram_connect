module InstagramConnect
  # A comment on one of the account's media objects. Upserted from the
  # `comments` webhook; moderation state (hidden/replied) is tracked here.
  class Comment < ApplicationRecord
    self.table_name = "instagram_connect_comments"

    belongs_to :account, class_name: "InstagramConnect::Account"

    validates :comment_id, presence: true, uniqueness: true

    scope :visible, -> { where(hidden_at: nil) }

    # Upsert by Meta comment id — the same comment can arrive more than once.
    def self.record(account:, comment_id:, media_id:, text:, from_username:, parent_id: nil)
      comment = find_or_initialize_by(comment_id: comment_id)
      comment.account = account
      comment.assign_attributes(media_id: media_id, text: text, from_username: from_username, parent_id: parent_id)
      comment.save!
      comment
    end

    def hidden?
      hidden_at.present?
    end
  end
end

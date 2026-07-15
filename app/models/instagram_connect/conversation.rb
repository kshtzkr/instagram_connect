module InstagramConnect
  # One DM thread — a connected account talking to one Instagram user (igsid).
  # Threads are shared across the host's operators; ownership lives on the
  # account, not per-operator.
  class Conversation < ApplicationRecord
    self.table_name = "instagram_connect_conversations"

    belongs_to :account, class_name: "InstagramConnect::Account"
    has_many :messages, class_name: "InstagramConnect::Message",
             foreign_key: :conversation_id, dependent: :destroy

    validates :igsid, presence: true, uniqueness: { scope: :account_id }

    scope :unread, -> { where("unread_count > 0") }
    scope :recent, -> { order(Arel.sql("last_message_at IS NULL, last_message_at DESC")) }

    # Race-safe find-or-create on the unique [account_id, igsid] pair.
    def self.locate(account:, igsid:)
      find_or_create_by!(account_id: account.id, igsid: igsid)
    rescue ActiveRecord::RecordNotUnique
      find_by!(account_id: account.id, igsid: igsid)
    end

    # Denormalizes the thread summary + unread count atomically (SQL-side) so
    # concurrent inbound writes can't lose an unread increment.
    def register_message(message)
      stamp = message.created_at || Time.current
      if message.inbound?
        self.class.where(id: id).update_all([
          "last_message_at = ?, last_message_preview = ?, last_inbound_at = ?, " \
          "unread_count = unread_count + 1, updated_at = ?",
          stamp, message.preview, stamp, Time.current
        ])
      else
        self.class.where(id: id).update_all([
          "last_message_at = ?, last_message_preview = ?, updated_at = ?",
          stamp, message.preview, Time.current
        ])
      end
      reload
    end
  end
end

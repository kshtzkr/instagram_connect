module InstagramConnect
  # One DM thread — a connected account talking to one Instagram user (igsid).
  # Threads are shared across the host's operators; ownership lives on the
  # account, not per-operator.
  #
  # Every writer here is SQL-side and monotonic. Meta guarantees no ordering
  # across webhook batches, so a late-arriving older event must not roll a
  # thread backwards, and concurrent inbound writes must not lose an unread
  # increment.
  class Conversation < ApplicationRecord
    self.table_name = "instagram_connect_conversations"

    FOLDERS = %w[primary general requests].freeze

    belongs_to :account, class_name: "InstagramConnect::Account"
    has_many :messages, class_name: "InstagramConnect::Message",
             foreign_key: :conversation_id, dependent: :destroy
    has_many :reactions, class_name: "InstagramConnect::MessageReaction",
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
    #
    # Keyed on the message's wire time, not our created_at: a webhook batch
    # delayed by a redeploy would otherwise stamp old messages as the newest
    # and reorder the inbox.
    def register_message(message)
      stamp = message.sent_at || message.created_at || Time.current
      assignments = [
        "last_message_at = #{monotonic('last_message_at')}",
        "last_message_preview = ?",
        "last_event_at = #{monotonic('last_event_at')}"
      ]
      binds = [ stamp, stamp, message.preview, stamp, stamp ]

      if message.inbound?
        assignments << "last_inbound_at = #{monotonic('last_inbound_at')}"
        assignments << "unread_count = unread_count + 1"
        binds += [ stamp, stamp ]
      end

      apply(assignments, binds)
    end

    # A read receipt only ever moves forward. A stale one redelivered after a
    # newer message must not mark the thread read again.
    def mark_read_by_customer(at:, mid: nil)
      apply(
        [
          "customer_last_read_mid = CASE WHEN customer_last_read_at IS NULL " \
          "OR customer_last_read_at < ? THEN ? ELSE customer_last_read_mid END",
          "customer_last_read_at = #{monotonic('customer_last_read_at')}",
          "last_event_at = #{monotonic('last_event_at')}"
        ],
        [ at, mid, at, at, at, at ]
      )
      mark_outbound_seen(at)
      self
    end

    def register_referral(ref:, at:)
      apply(
        [
          "last_referral_ref = CASE WHEN last_event_at IS NULL OR last_event_at < ? " \
          "THEN ? ELSE last_referral_ref END",
          "last_event_at = #{monotonic('last_event_at')}"
        ],
        [ at, ref, at, at ]
      )
    end

    def register_thread_control(owner_app_id:, at:)
      apply(
        [
          "thread_owner_app_id = CASE WHEN thread_control_at IS NULL OR thread_control_at < ? " \
          "THEN ? ELSE thread_owner_app_id END",
          "thread_control_at = #{monotonic('thread_control_at')}",
          "last_event_at = #{monotonic('last_event_at')}"
        ],
        [ at, owner_app_id, at, at, at, at ]
      )
    end

    # Any activity that is not a message — a reaction, an opt-in — still counts
    # as the thread being alive, and still reopens Meta's 24-hour window.
    def register_event(at)
      apply([ "last_event_at = #{monotonic('last_event_at')}" ], [ at, at ])
    end

    # True when another app (typically the Page Inbox) holds thread control, in
    # which case the Send API rejects our messages.
    def controlled_elsewhere?
      thread_control_at.present? && thread_owner_app_id.present?
    end

    private

    # SQLite has no GREATEST, so the monotonic guard is spelled as a CASE. Two
    # binds per use: the comparison value and the value to store.
    def monotonic(column)
      "CASE WHEN #{column} IS NULL OR #{column} < ? THEN ? ELSE #{column} END"
    end

    def apply(assignments, binds)
      self.class.where(id: id).update_all(
        [ "#{assignments.join(', ')}, updated_at = ?", *binds, Time.current ]
      )
      reload
    end

    # The receipt covers everything the customer had received, so every earlier
    # outbound message is seen too — Meta sends one receipt, not one per bubble.
    def mark_outbound_seen(at)
      messages.where(direction: "outbound", seen_at: nil)
              .where(sent_at: ..at)
              .update_all(seen_at: at, updated_at: Time.current)
    end
  end
end

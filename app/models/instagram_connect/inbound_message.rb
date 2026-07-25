module InstagramConnect
  # Dedupe ledger keyed by Meta's message id, scoped to an account.
  #
  # DEPRECATED, removal at 1.0. WebhookEvent is the claim now: keying every
  # event type on one message id is wrong once other fields carry the same id —
  # a messaging_seen receipt names the mid of a message already claimed here, so
  # claiming it would swallow either the receipt or the message. This is kept in
  # step so a host querying it against 0.2.x behaviour still sees every message.
  class InboundMessage < ApplicationRecord
    self.table_name = "instagram_connect_inbound_messages"

    # Returns true only the first time a message id is claimed for an account.
    # Uniqueness is scoped per account: two connected accounts messaging each
    # other share a mid, and a global claim would drop it for whichever account
    # processed second. A nil account_id therefore no longer dedupes at all.
    def self.claim(ig_message_id:, account_id: nil)
      create!(ig_message_id: ig_message_id, account_id: account_id, processed_at: Time.current)
      true
    rescue ActiveRecord::RecordNotUnique
      false
    end
  end
end

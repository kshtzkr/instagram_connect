module InstagramConnect
  # At-least-once dedupe ledger keyed by Meta's message id. Lets the webhook
  # (and any future backfill/poll) run without double-processing a message.
  class InboundMessage < ApplicationRecord
    self.table_name = "instagram_connect_inbound_messages"

    # Returns true only the first time a given message id is claimed.
    def self.claim(ig_message_id:, account_id: nil)
      create!(ig_message_id: ig_message_id, account_id: account_id, processed_at: Time.current)
      true
    rescue ActiveRecord::RecordNotUnique
      false
    end
  end
end

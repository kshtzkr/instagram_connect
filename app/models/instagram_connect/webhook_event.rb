module InstagramConnect
  # One row per webhook event Meta delivered, stored verbatim before anything
  # interprets it. See the migration for why this exists rather than a counter.
  class WebhookEvent < ApplicationRecord
    self.table_name = "instagram_connect_webhook_events"

    STATUSES = %w[pending processed unhandled failed].freeze

    belongs_to :account, class_name: "InstagramConnect::Account", optional: true
    belongs_to :subject, polymorphic: true, optional: true

    validates :field, :event_type, :dedupe_key, presence: true
    validates :status, inclusion: { in: STATUSES }

    scope :pending, -> { where(status: "pending") }
    scope :replayable, -> { where(status: %w[pending unhandled failed]) }
    scope :for_field, ->(field) { where(field: field) }
    scope :chronological, -> { order(:occurred_at, :id) }

    # Claims an event for processing, or returns nil if this exact event was
    # already delivered. Meta retries webhooks it considers unacknowledged, so
    # duplicates are routine rather than exceptional — the unique index on
    # [field, dedupe_key] is what makes the claim atomic under concurrency.
    def self.claim(field:, dedupe_key:, event_type:, payload:, account: nil,
                   object: nil, entry_id: nil, occurred_at: nil, handler: nil)
      create!(
        account: account,
        object: object,
        field: field,
        event_type: event_type,
        dedupe_key: dedupe_key,
        entry_id: entry_id,
        occurred_at: occurred_at,
        received_at: Time.current,
        handler: handler,
        payload: payload,
        status: "pending"
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def mark_processed!(subject = nil)
      update!(status: "processed", processed_at: Time.current, subject: subject)
    end

    # Recorded, not dropped: a field the gem does not parse yet is still worth
    # keeping, because replaying it later is the only way to recover events Meta
    # will never send again.
    def mark_unhandled!
      update!(status: "unhandled", processed_at: Time.current)
    end

    def mark_failed!(error)
      update!(
        status: "failed",
        processed_at: Time.current,
        error_class: error.class.name,
        error_message: error.message.to_s.truncate(1000)
      )
    end

    def processed?
      status == "processed"
    end
  end
end

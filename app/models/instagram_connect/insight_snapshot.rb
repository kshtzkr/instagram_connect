module InstagramConnect
  # One reading of a set of metrics, kept because Meta's own retention is short
  # and, for stories, measured in hours.
  class InsightSnapshot < ApplicationRecord
    self.table_name = "instagram_connect_insight_snapshots"

    SUBJECT_TYPES = %w[account media story].freeze
    SOURCES = %w[api webhook].freeze

    belongs_to :account, class_name: "InstagramConnect::Account"

    validates :subject_type, inclusion: { in: SUBJECT_TYPES }
    validates :source, inclusion: { in: SOURCES }
    validates :period, :period_start, :captured_at, presence: true

    scope :for_subject, ->(type, ref) { where(subject_type: type, subject_ref: ref) }
    scope :chronological, -> { order(:period_start, :id) }

    # Upsert on the natural key. The API poller overwrites its own reading as a
    # story accrues views; the webhook's final reading is a separate row because
    # source is part of the key, so neither can clobber the other.
    def self.record(account:, subject_type:, period:, period_start:, metrics:, captured_at:,
                    subject_ref: nil, breakdown: nil, source: "api", empty: false,
                    suppressed: false, error_code: nil)
      snapshot = find_or_initialize_by(
        account_id: account.id, subject_type: subject_type, subject_ref: subject_ref,
        period: period, period_start: period_start, breakdown: breakdown, source: source
      )
      snapshot.assign_attributes(
        metrics: metrics, captured_at: captured_at, empty: empty,
        suppressed: suppressed, error_code: error_code
      )
      snapshot.save!
      snapshot
    end

    # nil means Meta did not report the metric, which is not the same as zero —
    # so callers must never reach for a default here.
    def value(metric)
      metrics.is_a?(Hash) ? metrics[metric.to_s] : nil
    end
  end
end

module InstagramConnect
  # One file on a message. Rows are created at ingest with everything already
  # decided except the bytes, which a job fetches separately.
  class MessageAttachment < ApplicationRecord
    self.table_name = "instagram_connect_message_attachments"

    # Instagram gives no second chance at inbound media: the CDN URL expires and
    # there is no endpoint to ask again. So there is no "downloadable" state
    # here as there is for transports that keep the file — an attachment either
    # lands in storage or is permanently unavailable.
    STATES = %w[pending attached unavailable skipped].freeze

    # Meta's own vocabulary for what the attachment is, which is not the same
    # question as what MIME type the bytes turn out to be.
    KINDS = %w[image video audio file share story_mention ig_reel reel template].freeze

    belongs_to :message, class_name: "InstagramConnect::Message"


    validates :position, presence: true, uniqueness: { scope: :message_id }
    validates :kind, presence: true
    validates :state, inclusion: { in: STATES }

    # Called from the engine's to_prepare when Active Storage is present, the
    # same shape as Account.enable_token_encryption!. The gem does not depend on
    # Active Storage, so a host without it still boots and simply keeps the
    # attachment rows as metadata without ever fetching bytes.
    def self.enable_file_attachment!
      has_one_attached :file
    end

    scope :pending, -> { where(state: "pending") }
    scope :ordered, -> { order(:position) }

    def fetchable?
      state == "pending" && source_url.present?
    end

    def attached?
      state == "attached"
    end

    def mark_attached!(mime:, size:, filename: nil)
      update!(state: "attached", mime: mime, size: size, filename: filename, error: nil)
    end

    # Terminal. Nothing retries after this, because retrying a URL Instagram has
    # already expired only burns the rate budget.
    def mark_unavailable!(reason)
      update!(state: "unavailable", error: reason.to_s.truncate(255))
    end
  end
end

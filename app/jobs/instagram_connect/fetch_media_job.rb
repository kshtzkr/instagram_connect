require "httparty"

module InstagramConnect
  # Copies one inbound attachment's bytes out of Meta's CDN and into the host's
  # own storage.
  #
  # This runs against a clock nobody controls: Instagram's media URLs expire and
  # there is no endpoint to ask for a fresh one. So a failure here is permanent
  # for that file, which is why the retry ladder ends in a terminal state rather
  # than leaving the row pending — a pending attachment renders as a loading
  # placeholder, and one that never resolves is worse than an honest "this file
  # is no longer available".
  class FetchMediaJob < ApplicationJob
    queue_as :default

    TIMEOUT = 30
    TRANSPORT_ERRORS = [
      Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT,
      Net::OpenTimeout, Net::ReadTimeout, SocketError, IOError
    ].freeze

    retry_on(*TRANSPORT_ERRORS, attempts: 3, wait: :polynomially_longer) do |job, error|
      exhausted(job.arguments.first, error)
    end

    # Retries are spent. Without this the job would land in the dead set and
    # leave the attachment pending for ever — a loading placeholder in the
    # thread that nothing will ever resolve.
    def self.exhausted(attachment_id, error)
      MessageAttachment.find_by(id: attachment_id)&.mark_unavailable!("transport:#{error.class}")
    end

    def perform(attachment_id)
      attachment = MessageAttachment.find_by(id: attachment_id)
      return if attachment.nil?
      return unless storage_available?

      # The guard and the write have to be one atomic step: two deliveries of
      # the same webhook would otherwise both see "pending" and both fetch.
      attachment.with_lock do
        next unless attachment.fetchable?

        fetch_into(attachment)
      end
    end

    private

    def fetch_into(attachment)
      response = HTTParty.get(attachment.source_url, timeout: TIMEOUT, follow_redirects: true)
      unless response.success?
        # An expired CDN link is the common case and no amount of retrying
        # fixes it, so this is terminal rather than raised.
        attachment.mark_unavailable!("http_#{response.code}")
        return
      end

      verdict = Media::Attaching.evaluate(
        body: response.body,
        declared_mime: response.headers["content-type"],
        filename: attachment.filename
      )

      if verdict.ok?
        store(attachment, response.body, verdict)
      else
        attachment.mark_unavailable!(verdict.error)
      end
    ensure
      refresh_message_media_status(attachment)
    end

    def store(attachment, body, verdict)
      attachment.file.attach(
        io: StringIO.new(body),
        filename: attachment.filename.presence || default_filename(attachment, verdict.mime),
        content_type: verdict.mime
      )
      attachment.mark_attached!(mime: verdict.mime, size: verdict.size)
    end

    def default_filename(attachment, mime)
      extension = Rack::Mime::MIME_TYPES.invert[mime] || ""
      "instagram-#{attachment.id}#{extension}"
    end

    # The message carries the aggregate verdict across its attachments, so the
    # thread can show one state per bubble rather than one per file.
    def refresh_message_media_status(attachment)
      message = attachment.message
      return if message.nil?

      states = message.attachments.reload.pluck(:state)
      status = if states.include?("pending") then "pending"
      elsif states.any? { |s| s == "attached" } then "attached"
      elsif states.empty? then "none"
      else "unavailable"
      end

      Message.where(id: message.id).update_all(media_status: status, updated_at: Time.current)
      message.broadcast_refresh
    end

    # A host without Active Storage still receives messages; it simply keeps the
    # attachment rows as metadata and never fetches bytes.
    def storage_available?
      defined?(ActiveStorage::Blob).present?
    end
  end
end

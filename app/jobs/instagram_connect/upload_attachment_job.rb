module InstagramConnect
  # Uploads a message's file to Meta and records the reusable attachment id,
  # then hands the message to the sender.
  #
  # Two steps rather than one because Meta's upload is a separate call with its
  # own failure mode: a file it rejects (too large, wrong type) must fail the
  # message with THAT reason, not with whatever the send would have said
  # afterwards. The id is reusable, so the same file sent to a second thread
  # costs no upload at all.
  #
  # The host attaches the file however it likes (Active Storage, a Tempfile);
  # this job only needs something that responds to #open or #path.
  class UploadAttachmentJob < ApplicationJob
    queue_as :default

    # Meta's own ceilings, stated here so a file that cannot possibly work is
    # refused before it costs an upload.
    SIZE_LIMITS = { "image" => 8.megabytes, "video" => 25.megabytes,
                    "audio" => 25.megabytes, "file" => 25.megabytes }.freeze

    def perform(message_id, file_path, type: "image")
      message = Message.find_by(id: message_id)
      return if message.nil? || message.attachment_upload_id.present?

      unless File.exist?(file_path)
        return fail_message(message, "attachment_missing",
                            "The file to send could not be read.")
      end

      limit = SIZE_LIMITS.fetch(type, SIZE_LIMITS["file"])
      if File.size(file_path) > limit
        return fail_message(message, "attachment_too_large",
                            "Instagram refuses #{type}s over #{limit / 1.megabyte}MB.")
      end

      upload(message, file_path, type)
    end

    private

    def upload(message, file_path, type)
      result = File.open(file_path) do |file|
        message.conversation.account.client.upload_attachment(file: file, type: type)
      end

      unless result.success?
        return fail_message(message, result.error_code&.to_s, result.error_message)
      end

      attachment_id = result.data["attachment_id"].presence || result.id
      if attachment_id.blank?
        return fail_message(message, "attachment_upload_empty",
                            "Instagram accepted the upload but returned no attachment id.")
      end

      message.update!(attachment_upload_id: attachment_id, media_kind: type)
      SendMessageJob.perform_later(message.id)
    end

    def fail_message(message, reason, error)
      message.update!(status: "failed", failure_reason: reason, error_message: error)
      message.broadcast_refresh
      nil
    end
  end
end

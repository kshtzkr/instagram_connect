require "rails_helper"

# Sending a photo or a video in a DM is most of what Instagram messaging IS,
# and the client methods for it had zero callers: upload_attachment and
# send_attachment existed, nothing used them, and the composer was text-only.
RSpec.describe "sending an attachment" do
  let(:base) { "https://graph.facebook.com/v21.0" }
  let(:json) { { "Content-Type" => "application/json" } }

  let!(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGUSER", auth_path: "facebook_login",
                                      access_token: "tok", page_id: "PAGE1", active: true)
  end
  let!(:conversation) do
    InstagramConnect::Conversation.create!(account: account, igsid: "CUST1",
                                           last_inbound_at: 1.hour.ago)
  end
  let!(:message) do
    InstagramConnect::Message.create!(conversation: conversation, direction: "outbound",
                                      status: "pending", kind: "dm", source: "manual",
                                      body: "Here it is")
  end

  let(:file_path) do
    path = Rails.root.join("tmp", "attachment-spec.jpg")
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, "x" * 1024)
    path.to_s
  end

  after { FileUtils.rm_f(file_path) }

  def stub_upload(attachment_id: "att-1")
    stub_request(:post, "#{base}/me/message_attachments")
      .to_return(status: 200, body: { attachment_id: attachment_id }.to_json, headers: json)
  end

  def stub_send
    stub_request(:post, "#{base}/me/messages")
      .to_return(status: 200, body: { message_id: "mid-1" }.to_json, headers: json)
  end

  describe "the upload half" do
    it "records Meta's reusable id and hands the message on to the sender" do
      stub_upload

      expect {
        InstagramConnect::UploadAttachmentJob.perform_now(message.id, file_path, type: "image")
      }.to have_enqueued_job(InstagramConnect::SendMessageJob).with(message.id)

      expect(message.reload.attachment_upload_id).to eq("att-1")
      expect(message.media_kind).to eq("image")
    end

    it "refuses a file over Meta's ceiling before spending an upload" do
      File.binwrite(file_path, "x" * 9.megabytes)

      InstagramConnect::UploadAttachmentJob.perform_now(message.id, file_path, type: "image")

      expect(message.reload.status).to eq("failed")
      expect(message.error_message).to match(/over 8MB/)
      expect(WebMock).not_to have_requested(:post, "#{base}/me/message_attachments")
    end

    it "fails with the upload's own reason, not the send's" do
      stub_request(:post, "#{base}/me/message_attachments")
        .to_return(status: 400,
                   body: { error: { message: "Unsupported post request", code: 100 } }.to_json,
                   headers: json)

      InstagramConnect::UploadAttachmentJob.perform_now(message.id, file_path, type: "image")

      expect(message.reload.status).to eq("failed")
      expect(message.error_message).to match(/Unsupported post request/)
    end

    it "says so when Meta accepts the upload but returns no id" do
      stub_request(:post, "#{base}/me/message_attachments")
        .to_return(status: 200, body: {}.to_json, headers: json)

      InstagramConnect::UploadAttachmentJob.perform_now(message.id, file_path, type: "image")

      expect(message.reload.failure_reason).to eq("attachment_upload_empty")
    end

    it "says so when the file has gone missing" do
      InstagramConnect::UploadAttachmentJob.perform_now(message.id, "/nope/gone.jpg", type: "image")

      expect(message.reload.failure_reason).to eq("attachment_missing")
    end

    # Meta does not always attach a numeric code to a refusal.
    it "survives an upload refusal that carries no error code" do
      stub_request(:post, "#{base}/me/message_attachments")
        .to_return(status: 400, body: { error: { message: "Bad file" } }.to_json, headers: json)

      InstagramConnect::UploadAttachmentJob.perform_now(message.id, file_path, type: "image")

      expect(message.reload.status).to eq("failed")
      expect(message.failure_reason).to be_nil
      expect(message.error_message).to match(/Bad file/)
    end

    it "falls back to the plain id when Meta names it differently" do
      stub_request(:post, "#{base}/me/message_attachments")
        .to_return(status: 200, body: { id: "att-fallback" }.to_json, headers: json)

      InstagramConnect::UploadAttachmentJob.perform_now(message.id, file_path, type: "image")

      expect(message.reload.attachment_upload_id).to eq("att-fallback")
    end

    it "holds an unknown type to the general file ceiling" do
      File.binwrite(file_path, "x" * 26.megabytes)

      InstagramConnect::UploadAttachmentJob.perform_now(message.id, file_path, type: "sticker")

      expect(message.reload.error_message).to match(/over 25MB/)
    end

    it "does nothing for a missing message or one already uploaded" do
      message.update!(attachment_upload_id: "already")
      stub_upload

      InstagramConnect::UploadAttachmentJob.perform_now(message.id, file_path)
      InstagramConnect::UploadAttachmentJob.perform_now(0, file_path)

      expect(WebMock).not_to have_requested(:post, "#{base}/me/message_attachments")
    end
  end

  describe "the send half" do
    before { message.update!(attachment_upload_id: "att-1") }

    it "sends the attachment before the words about it" do
      stub_send

      InstagramConnect::SendMessageJob.perform_now(message.id)

      expect(message.reload.status).to eq("sent")
      expect(message.attachment_delivered_at).to be_present
      expect(WebMock).to have_requested(:post, "#{base}/me/messages")
        .with { |req| req.body.include?("attachment_id") }.once
      expect(WebMock).to have_requested(:post, "#{base}/me/messages")
        .with { |req| req.body.include?("Here it is") }.once
    end

    it "sends an attachment-only message with no text call at all" do
      message.update!(body: nil)
      stub_send

      InstagramConnect::SendMessageJob.perform_now(message.id)

      expect(message.reload.status).to eq("sent")
      expect(WebMock).to have_requested(:post, "#{base}/me/messages").once
    end

    # A worker killed between the two halves must not show the customer the
    # photo twice.
    it "does not re-send an attachment a resumed job already delivered" do
      message.update!(attachment_delivered_at: 1.minute.ago)
      stub_send

      InstagramConnect::SendMessageJob.perform_now(message.id)

      expect(WebMock).not_to have_requested(:post, "#{base}/me/messages")
        .with { |req| req.body.include?("attachment_id") }
    end

    it "survives an attachment refusal that carries no error code" do
      stub_request(:post, "#{base}/me/messages")
        .to_return(status: 400, body: { error: { message: "Nope" } }.to_json, headers: json)

      InstagramConnect::SendMessageJob.perform_now(message.id)

      expect(message.reload.status).to eq("failed")
      expect(message.failure_reason).to be_nil
    end

    it "keeps the id the message already had rather than the attachment's" do
      message.update!(ig_message_id: "mid-original")
      stub_send

      InstagramConnect::SendMessageJob.perform_now(message.id)

      expect(message.reload.ig_message_id).to eq("mid-original")
    end

    it "fails the message when Meta refuses the attachment, and sends no text" do
      stub_request(:post, "#{base}/me/messages")
        .to_return(status: 400,
                   body: { error: { message: "Attachment size exceeds allowable limit",
                                    code: 100 } }.to_json, headers: json)

      InstagramConnect::SendMessageJob.perform_now(message.id)

      expect(message.reload.status).to eq("failed")
      expect(message.error_message).to match(/size exceeds/)
      expect(WebMock).to have_requested(:post, "#{base}/me/messages").once
    end
  end
end

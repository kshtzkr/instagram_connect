require "rails_helper"

RSpec.describe InstagramConnect::FetchMediaJob do
  let(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "t")
  end
  let(:conversation) { InstagramConnect::Conversation.locate(account: account, igsid: "CUST") }
  let(:message) do
    conversation.messages.create!(direction: "inbound", status: "received", kind: "dm",
                                  media_status: "pending", sent_at: Time.current)
  end
  let(:jpeg) { "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00#{'padding' * 20}".b }

  def attachment(state: "pending", url: "https://cdn.example/a.jpg", position: 0)
    InstagramConnect::MessageAttachment.create!(
      message: message, position: position, kind: "image", state: state, source_url: url
    )
  end

  def stub_download(body:, code: 200, content_type: "image/jpeg")
    stub_request(:get, "https://cdn.example/a.jpg")
      .to_return(status: code, body: body, headers: { "Content-Type" => content_type })
  end

  it "stores the bytes and records what they turned out to be" do
    record = attachment
    stub_download(body: jpeg)

    described_class.perform_now(record.id)

    record.reload
    expect(record.state).to eq("attached")
    expect(record.mime).to eq("image/jpeg")
    expect(record.size).to eq(jpeg.bytesize)
    expect(record.file).to be_attached
    expect(message.reload.media_status).to eq("attached")
  end

  # Instagram's CDN links expire and there is no endpoint to ask again, so a
  # failure is permanent for that file. Leaving it pending would render a
  # loading placeholder in the thread for ever.
  it "marks an expired link unavailable rather than retrying it" do
    record = attachment
    stub_download(body: "gone", code: 404)

    described_class.perform_now(record.id)

    expect(record.reload.state).to eq("unavailable")
    expect(record.error).to eq("http_404")
    expect(message.reload.media_status).to eq("unavailable")
  end

  it "refuses a file whose bytes do not match an allowed type" do
    record = attachment
    stub_download(body: "<html>not an image</html>", content_type: "image/jpeg")

    described_class.perform_now(record.id)

    expect(record.reload.state).to eq("unavailable")
    expect(record.error).to start_with("type_not_allowed")
  end

  it "does nothing for an attachment that already resolved" do
    record = attachment(state: "attached")

    described_class.perform_now(record.id)

    expect(WebMock).not_to have_requested(:get, "https://cdn.example/a.jpg")
  end

  it "does nothing for an attachment with no URL to fetch" do
    record = attachment(url: nil, state: "pending")

    expect { described_class.perform_now(record.id) }.not_to raise_error
    expect(record.reload.state).to eq("pending")
  end

  it "tolerates the attachment having been deleted before the job ran" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it "keeps the message pending while any sibling is still unresolved" do
    stub_download(body: jpeg)
    first = attachment(position: 0)
    attachment(position: 1, url: nil)
    InstagramConnect::MessageAttachment.find_by(position: 1).update!(state: "pending")

    described_class.perform_now(first.id)

    expect(message.reload.media_status).to eq("pending")
  end

  it "reports the message as having no media when it has no attachments at all" do
    record = attachment
    stub_download(body: jpeg)
    described_class.perform_now(record.id)
    record.destroy!

    described_class.send(:new).send(:refresh_message_media_status, record)

    expect(message.reload.media_status).to eq("none")
  end

  # Without this the job lands in the dead set and the attachment stays pending
  # for ever, which renders as a placeholder nothing will ever resolve.
  it "marks the attachment unavailable once its retries are spent" do
    record = attachment

    described_class.exhausted(record.id, Errno::ECONNRESET.new)

    expect(record.reload.state).to eq("unavailable")
    expect(record.error).to start_with("transport:")
  end

  it "runs the exhaust handler through the retry ladder, not only when called directly" do
    record = attachment
    stub_request(:get, "https://cdn.example/a.jpg").to_raise(SocketError)

    perform_enqueued_jobs do
      described_class.perform_later(record.id)
    end

    expect(record.reload.state).to eq("unavailable")
  end

  it "tolerates the attachment having been deleted before the retries ran out" do
    expect { described_class.exhausted(-1, SocketError.new) }.not_to raise_error
  end

  it "fetches nothing in a host that has no Active Storage" do
    record = attachment
    allow_any_instance_of(described_class).to receive(:storage_available?).and_return(false)

    described_class.perform_now(record.id)

    expect(WebMock).not_to have_requested(:get, "https://cdn.example/a.jpg")
    expect(record.reload.state).to eq("pending")
  end

  it "skips the message rollup for an attachment with no message" do
    orphan = InstagramConnect::MessageAttachment.new(position: 0, kind: "image")

    expect { described_class.send(:new).send(:refresh_message_media_status, orphan) }.not_to raise_error
  end

  it "asks the host to re-render, since the status was written callback-free" do
    record = attachment
    stub_download(body: jpeg)
    allow_any_instance_of(InstagramConnect::Message).to receive(:broadcast_refresh)

    described_class.perform_now(record.id)

    expect(message.reload.media_status).to eq("attached")
  end
end

require "rails_helper"

RSpec.describe InstagramConnect::MessageAttachment do
  let(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "t")
  end
  let(:conversation) { InstagramConnect::Conversation.locate(account: account, igsid: "CUST") }
  let(:message) do
    conversation.messages.create!(direction: "inbound", status: "received", kind: "dm")
  end

  def build(**attrs)
    described_class.create!({ message: message, position: 0, kind: "image" }.merge(attrs))
  end

  it "is only fetchable while pending and holding a URL" do
    expect(build(source_url: "https://cdn.example/a.jpg")).to be_fetchable
    expect(build(position: 1, source_url: nil)).not_to be_fetchable
    expect(build(position: 2, source_url: "https://x", state: "attached")).not_to be_fetchable
  end

  it "reports whether the bytes landed" do
    attachment = build(source_url: "https://x")

    expect(attachment).not_to be_attached
    attachment.mark_attached!(mime: "image/jpeg", size: 100)
    expect(attachment).to be_attached
  end

  it "clears any earlier error when the bytes finally land" do
    attachment = build(source_url: "https://x", error: "earlier")

    attachment.mark_attached!(mime: "image/jpeg", size: 100, filename: "a.jpg")

    expect(attachment.error).to be_nil
    expect(attachment.filename).to eq("a.jpg")
  end

  it "truncates a long failure reason rather than bloating the row" do
    attachment = build(source_url: "https://x")

    attachment.mark_unavailable!("x" * 500)

    expect(attachment.error.length).to eq(255)
  end

  it "keeps positions unique within a message" do
    build(source_url: "https://x")

    expect { build(source_url: "https://y") }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "rejects a state it does not recognise" do
    expect(described_class.new(message: message, position: 0, kind: "image", state: "downloading"))
      .not_to be_valid
  end
end

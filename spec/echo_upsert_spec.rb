require "rails_helper"

# Production, 2026-07-27: the hourly replay logged, for event after event,
#   [InstagramConnect] replay failed for event=2 field=message_echoes:
#   PG::UniqueViolation ... "index_instagram_connect_messages_on_account_and_mid"
# Every message the CMS sends stores Meta's mid; the echo of that same message
# then arrives and the handler called create! on the same mid. The event was
# banked failed, and every replay of it failed again — forever.
RSpec.describe InstagramConnect::Ingest::Handlers::Messages, "echo of a message we already sent" do
  let!(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGUSER", auth_path: "facebook_login",
                                      access_token: "tok", active: true)
  end
  let!(:conversation) do
    InstagramConnect::Conversation.create!(account: account, igsid: "CUST1")
  end
  let!(:sent) do
    InstagramConnect::Message.create!(
      conversation: conversation, direction: "outbound", status: "sent",
      source: "manual", kind: "dm", body: "Here is the itinerary",
      ig_message_id: "mid-echo-1"
    )
  end

  def echo_envelope(**overrides)
    event = {
      "sender" => { "id" => account.ig_user_id },
      "recipient" => { "id" => "CUST1" },
      "timestamp" => 1_753_600_000_000,
      "message" => { "mid" => "mid-echo-1", "text" => "Here is the itinerary",
                     "is_echo" => true }.merge(overrides)
    }
    InstagramConnect::Ingest::Envelope.new(
      account: account, field: "messages", event: event,
      object: "instagram", entry_id: account.ig_user_id,
      occurred_at: Time.zone.at(1_753_600_000)
    )
  end

  it "confirms the message instead of duplicating it" do
    expect {
      described_class.new(echo_envelope).call
    }.not_to change(InstagramConnect::Message, :count)

    expect(sent.reload.ig_message_id).to eq("mid-echo-1")
  end

  it "does not rewrite how the message was sent" do
    described_class.new(echo_envelope).call

    sent.reload
    # An echo must not turn a CMS-sent message into one that looks sent from
    # the phone — direction, status, source and body stay as first written.
    expect(sent.source).to eq("manual")
    expect(sent.status).to eq("sent")
    expect(sent.direction).to eq("outbound")
    expect(sent.body).to eq("Here is the itinerary")
  end

  it "fills in what the original write could not know" do
    expect(sent.sent_at).to be_nil

    described_class.new(echo_envelope).call

    expect(sent.reload.sent_at).to be_present
  end

  it "still stores a first echo of a message this system never sent" do
    envelope = echo_envelope("mid" => "mid-never-seen")

    expect {
      described_class.new(envelope).call
    }.to change(InstagramConnect::Message, :count).by(1)

    expect(InstagramConnect::Message.find_by(ig_message_id: "mid-never-seen").direction)
      .to eq("outbound")
  end

  it "leaves an already-complete row untouched" do
    sent.update!(sent_at: 3.days.ago, media_status: "none", story_id: "s-1",
                 story_url: "https://cdn/s1", media_kind: "image")
    before = sent.reload.updated_at

    described_class.new(echo_envelope).call

    expect(sent.reload.updated_at).to eq(before)
    expect(sent.sent_at).to be_within(1.second).of(3.days.ago)
    expect(sent.story_id).to eq("s-1")
  end

  it "adds the echo's attachments once, and not again on replay" do
    envelope = echo_envelope(
      "attachments" => [ { "type" => "image",
                           "payload" => { "url" => "https://cdn.example/pic.jpg" } } ]
    )

    described_class.new(envelope).call
    expect(sent.reload.attachments.count).to eq(1)

    described_class.new(envelope).call
    expect(sent.reload.attachments.count).to eq(1)
  end

  it "fills story context the original send never had" do
    # Story context rides inside the attachment payload, not reply_to.
    envelope = echo_envelope(
      "attachments" => [ { "type" => "story_mention",
                           "payload" => { "story" => { "id" => "story-9",
                                                       "url" => "https://cdn/story9" } } } ]
    )

    described_class.new(envelope).call

    sent.reload
    expect(sent.story_id).to eq("story-9")
    expect(sent.story_url).to eq("https://cdn/story9")
  end

  # Without a mid there is nothing to match on, so the echo cannot be tied to
  # an existing row and is stored on its own.
  it "stores an echo that carries no mid at all" do
    envelope = echo_envelope
    envelope.event["message"].delete("mid")

    expect {
      described_class.new(envelope).call
    }.to change(InstagramConnect::Message, :count).by(1)
  end

  it "is safe to replay any number of times" do
    3.times { described_class.new(echo_envelope).call }

    expect(InstagramConnect::Message.where(ig_message_id: "mid-echo-1").count).to eq(1)
  end
end

require "rails_helper"

RSpec.describe InstagramConnect::ReplayEventsJob do
  let!(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "t")
  end

  def bank(field:, dedupe_key:, payload:, account_record: account, status: "unhandled")
    event = InstagramConnect::WebhookEvent.claim(
      field: field, dedupe_key: dedupe_key, event_type: field,
      payload: payload, account: account_record, entry_id: "IGACC"
    )
    event.mark_unhandled! if status == "unhandled"
    event.mark_failed!(StandardError.new("earlier bug")) if status == "failed"
    event
  end

  def message_payload(mid)
    {
      "sender" => { "id" => "CUST" }, "recipient" => { "id" => "IGACC" },
      "message" => { "mid" => mid, "text" => "banked" }
    }
  end

  # The whole point of the ledger: a field subscribed before its handler shipped
  # banks as unhandled, and replaying reconstructs the history Meta will never
  # send again.
  it "processes a banked event once a handler exists" do
    event = bank(field: "messages", dedupe_key: "m1", payload: message_payload("m1"))

    described_class.perform_now

    expect(event.reload.status).to eq("processed")
    expect(InstagramConnect::Message.find_by(ig_message_id: "m1").body).to eq("banked")
    expect(event.subject).to eq(InstagramConnect::Message.last)
  end

  it "retries an event a bug had failed, and counts the attempt" do
    event = bank(field: "messages", dedupe_key: "m2", payload: message_payload("m2"), status: "failed")

    described_class.perform_now

    expect(event.reload.status).to eq("processed")
    expect(event.attempts).to eq(1)
  end

  it "leaves an event alone when nothing can parse its field yet" do
    event = bank(field: "response_feedback", dedupe_key: "s1", payload: { "feedback" => "x" })

    described_class.perform_now

    expect(event.reload.status).to eq("unhandled")
  end

  it "leaves an event alone when its account is still unknown" do
    event = bank(field: "messages", dedupe_key: "m3", payload: message_payload("m3"), account_record: nil)

    described_class.perform_now

    expect(event.reload.status).to eq("unhandled")
    expect(InstagramConnect::Message.count).to eq(0)
  end

  it "never touches an event that already succeeded" do
    event = bank(field: "messages", dedupe_key: "m4", payload: message_payload("m4"))
    event.mark_processed!

    expect { described_class.perform_now }.not_to change { event.reload.updated_at }
  end

  it "records a replay that fails again rather than losing the row" do
    event = bank(field: "messages", dedupe_key: "m5", payload: message_payload("m5"))
    allow(InstagramConnect::Conversation).to receive(:locate).and_raise(ArgumentError, "still broken")

    described_class.perform_now

    expect(event.reload.status).to eq("failed")
    expect(event.error_class).to eq("ArgumentError")
  end

  it "records a repeat failure even when the host configured no logger" do
    event = bank(field: "messages", dedupe_key: "m5b", payload: message_payload("m5b"))
    InstagramConnect.configuration.logger = nil
    allow(InstagramConnect::Conversation).to receive(:locate).and_raise(ArgumentError, "still broken")

    expect { described_class.perform_now }.not_to raise_error
    expect(event.reload.status).to eq("failed")
  end

  it "replays only the requested field" do
    messages = bank(field: "messages", dedupe_key: "m6", payload: message_payload("m6"))
    comments = bank(field: "comments", dedupe_key: "c1", payload: { "value" => { "id" => "c1", "text" => "hi" } })

    described_class.perform_now(field: "comments")

    expect(messages.reload.status).to eq("unhandled")
    expect(comments.reload.status).to eq("processed")
  end

  it "replays only events banked since a cutoff" do
    old = bank(field: "messages", dedupe_key: "m7", payload: message_payload("m7"))
    old.update!(created_at: 3.days.ago)
    recent = bank(field: "messages", dedupe_key: "m8", payload: message_payload("m8"))

    described_class.perform_now(since: 1.day.ago)

    expect(old.reload.status).to eq("unhandled")
    expect(recent.reload.status).to eq("processed")
  end

  it "caps how many it takes in one pass" do
    bank(field: "messages", dedupe_key: "m9", payload: message_payload("m9"))
    bank(field: "messages", dedupe_key: "m10", payload: message_payload("m10"))

    described_class.perform_now(limit: 1)

    expect(InstagramConnect::WebhookEvent.where(status: "processed").count).to eq(1)
  end
end

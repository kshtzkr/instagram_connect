require "rails_helper"

RSpec.describe InstagramConnect::Ingest::Dispatcher do
  let!(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "t")
  end
  let(:config) { InstagramConnect.configuration }

  def dm(mid:, text: "hi")
    {
      "object" => "instagram",
      "entry" => [ {
        "id" => "IGACC", "time" => 1_700_000_000_000,
        "messaging" => [ {
          "sender" => { "id" => "CUST" }, "recipient" => { "id" => "IGACC" },
          "timestamp" => 1_700_000_001_000,
          "message" => { "mid" => mid, "text" => text }
        } ]
      } ]
    }
  end

  def run(payload) = described_class.new(config).call(payload)

  it "stamps the event with Meta's wire clock, not our own" do
    run(dm(mid: "m1"))

    event = InstagramConnect::WebhookEvent.last
    expect(event.occurred_at.to_i).to eq(1_700_000_001)
    expect(event.object).to eq("instagram")
    expect(event.entry_id).to eq("IGACC")
    expect(event.handler).to eq("InstagramConnect::Ingest::Handlers::Messages")
  end

  it "falls back to the entry's time when the event carries none" do
    payload = dm(mid: "m1")
    payload["entry"].first["messaging"].first.delete("timestamp")

    run(payload)

    expect(InstagramConnect::WebhookEvent.last.occurred_at.to_i).to eq(1_700_000_000)
  end

  it "links the event to the row it produced" do
    run(dm(mid: "m1"))

    event = InstagramConnect::WebhookEvent.last
    expect(event.subject).to eq(InstagramConnect::Message.last)
  end

  # One malformed event must not cost the rest of the batch. Meta batches
  # several entries per delivery and never re-sends, so aborting on the first
  # error would lose every event behind it.
  it "fails one event and still processes its neighbours" do
    allow(InstagramConnect::Conversation).to receive(:locate).and_call_original
    allow(InstagramConnect::Conversation).to receive(:locate)
      .with(hash_including(igsid: "BAD")).and_raise(ArgumentError, "boom")

    payload = dm(mid: "ok1")
    payload["entry"].first["messaging"].unshift(
      "sender" => { "id" => "BAD" }, "recipient" => { "id" => "IGACC" },
      "message" => { "mid" => "bad1", "text" => "x" }
    )

    summary = run(payload)

    expect(summary[:failed]).to eq(1)
    expect(summary[:messages]).to eq(1)
    expect(InstagramConnect::WebhookEvent.find_by(dedupe_key: "bad1").status).to eq("failed")
    expect(InstagramConnect::WebhookEvent.find_by(dedupe_key: "bad1").error_class).to eq("ArgumentError")
  end

  # The rows are committed by the time a callback runs. Letting a host hook
  # flip the event to failed would have it replayed and the data duplicated.
  it "does not fail an event when the host's callback raises" do
    config.on_message = ->(_message) { raise "host exploded" }

    summary = run(dm(mid: "m1"))

    expect(summary[:callback_errors]).to eq(1)
    expect(summary[:messages]).to eq(1)
    expect(InstagramConnect::WebhookEvent.last.status).to eq("processed")
  end

  it "survives a host callback raising when the host also configured no logger" do
    config.on_message = ->(_message) { raise "host exploded" }
    config.logger = nil

    expect { run(dm(mid: "m1")) }.not_to raise_error
    expect(InstagramConnect::WebhookEvent.last.status).to eq("processed")
  end

  it "banks a malformed event once, however many times Meta redelivers it" do
    payload = dm(mid: "")

    run(payload)
    summary = run(payload)

    expect(summary[:duplicates]).to eq(1)
    expect(InstagramConnect::WebhookEvent.count).to eq(1)
  end

  it "ignores a callback that is not callable" do
    config.on_message = "not a lambda"

    expect { run(dm(mid: "m1")) }.not_to raise_error
    expect(InstagramConnect::WebhookEvent.last.status).to eq("processed")
  end

  it "hashes a payload that carries no id of its own, so it still dedupes" do
    payload = {
      "object" => "instagram",
      "entry" => [ { "id" => "IGACC", "changes" => [ { "field" => "story_insights", "value" => { "x" => 1 } } ] } ]
    }

    run(payload)
    summary = run(payload)

    expect(summary[:duplicates]).to eq(1)
    expect(InstagramConnect::WebhookEvent.count).to eq(1)
    expect(InstagramConnect::WebhookEvent.last.dedupe_key.length).to eq(64)
  end

  it "reads standby events as their own field" do
    payload = {
      "object" => "instagram",
      "entry" => [ { "id" => "IGACC", "standby" => [ { "message" => { "mid" => "s1" } } ] } ]
    }

    run(payload)

    expect(InstagramConnect::WebhookEvent.last.field).to eq("standby")
  end

  it "ignores an entry with no id at all" do
    summary = run("object" => "instagram", "entry" => [ { "messaging" => [] } ])

    expect(summary[:messages]).to eq(0)
    expect(InstagramConnect::WebhookEvent.count).to eq(0)
  end

  it "keeps the legacy InboundMessage ledger in step for 0.2.x hosts" do
    run(dm(mid: "m1"))

    expect(InstagramConnect::InboundMessage.find_by(ig_message_id: "m1")).to be_present
  end

  it "banks a duplicate arriving in the same delivery only once" do
    payload = dm(mid: "same")
    payload["entry"].first["messaging"] << payload["entry"].first["messaging"].first.dup

    summary = run(payload)

    expect(summary[:messages]).to eq(1)
    expect(summary[:duplicates]).to eq(1)
  end
end

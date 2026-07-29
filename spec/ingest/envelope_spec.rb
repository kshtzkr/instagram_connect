require "rails_helper"

RSpec.describe InstagramConnect::Ingest::Envelope do
  describe ".time_from" do
    # Meta sends milliseconds. Reading them as seconds would date every message
    # to the year 55000 and reorder every thread.
    it "reads Meta's millisecond timestamps" do
      expect(described_class.time_from(1_700_000_001_000).to_i).to eq(1_700_000_001)
    end

    it "returns nil when the event carries no timestamp" do
      expect(described_class.time_from(nil)).to be_nil
    end

    it "returns nil rather than raising on a value it cannot read" do
      expect(described_class.time_from("not a time")).to eq(Time.at(0).utc)
      expect(described_class.time_from(10**30)).to be_nil
    end
  end

  it "digs into the wrapped event" do
    envelope = described_class.new(event: { "sender" => { "id" => "CUST" } })

    expect(envelope.dig("sender", "id")).to eq("CUST")
  end
  # Production, 2026-07-28: Meta stamps messaging webhooks in MILLISECONDS but
  # comment-change webhooks in SECONDS. Everything divided by 1000 turned
  # every comment's clock into January 1970 — read as "older than the 7-day
  # reply window", silently skipping every realtime comment automation.
  describe "unit detection" do
    it "reads a seconds timestamp as seconds" do
      now = Time.now.to_i

      expect(described_class.time_from(now).to_i).to eq(now)
    end

    it "still reads a milliseconds timestamp as milliseconds" do
      now = Time.now.to_i

      expect(described_class.time_from(now * 1000).to_i).to eq(now)
    end

    it "reads string values either way" do
      now = Time.now.to_i

      expect(described_class.time_from(now.to_s).to_i).to eq(now)
      expect(described_class.time_from((now * 1000).to_s).to_i).to eq(now)
    end
  end

end

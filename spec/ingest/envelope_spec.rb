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
end

require "rails_helper"

RSpec.describe InstagramConnect::Ingest::Summary do
  subject(:summary) { described_class.new }

  it "starts at zero on every counter" do
    expect(summary.to_h.values).to all(eq(0))
  end

  it "counts echoes as messages and live comments as comments" do
    summary.count("message_echoes")
    summary.count("live_comments")
    summary.count("messaging_postbacks")

    expect(summary.to_h).to include(messages: 1, comments: 1, postbacks: 1)
  end

  it "ignores a field with no counter of its own" do
    expect { summary.count("story_insights") }.not_to change(summary, :to_h)
  end

  # 0.2.x reported one `skipped` figure. Splitting it was the point — duplicates
  # are healthy, unhandled events are a backlog — but hosts reading the old key
  # must keep working.
  it "keeps skipped as duplicates plus unhandled" do
    summary.duplicates = 2
    summary.unhandled = 3

    expect(summary.skipped).to eq(5)
    expect(summary[:skipped]).to eq(5)
    expect(summary["skipped"]).to eq(5)
  end

  it "converts implicitly to a Hash, so it can stand in for the old return value" do
    summary.messages = 1

    expect(summary.to_hash).to eq(summary.to_h)
    expect(Hash(summary)).to include(messages: 1)
  end

  it "compares equal to the hash it represents" do
    expect(summary).to eq(summary.to_h)
    expect(summary).not_to eq(42)
  end

  it "enumerates its counters" do
    expect(summary.map { |key, _value| key }).to include(:messages, :duplicates, :failed)
  end
end

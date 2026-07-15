require "instagram_connect"

RSpec.describe InstagramConnect::MessagingWindow do
  let(:now) { Time.now }

  def window(seconds_ago)
    last = seconds_ago.nil? ? nil : now - seconds_ago
    described_class.new(last_inbound_at: last, now: now)
  end

  it "is standard within 24 hours" do
    w = window(3600)
    expect(w.state).to eq(:standard)
    expect(w).to be_standard
    expect(w).to be_open
    expect(w.send_tag).to be_nil
  end

  it "is human_agent between 24 hours and 7 days" do
    w = window(3 * 24 * 3600)
    expect(w.state).to eq(:human_agent)
    expect(w).to be_open
    expect(w).not_to be_standard
    expect(w.send_tag).to eq("HUMAN_AGENT")
  end

  it "is closed beyond 7 days" do
    w = window(8 * 24 * 3600)
    expect(w.state).to eq(:closed)
    expect(w).not_to be_open
    expect(w.send_tag).to eq(:blocked)
  end

  it "is closed when there was never an inbound message" do
    expect(window(nil).state).to eq(:closed)
  end

  it "treats exactly 24 hours as still standard" do
    expect(window(24 * 3600).state).to eq(:standard)
  end

  it "treats exactly 7 days as still human_agent" do
    expect(window(7 * 24 * 3600).state).to eq(:human_agent)
  end
end

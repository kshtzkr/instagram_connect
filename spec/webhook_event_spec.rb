require "rails_helper"

RSpec.describe InstagramConnect::WebhookEvent do
  let(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "t")
  end

  def claim(overrides = {})
    described_class.claim(**{
      field: "messages", dedupe_key: "mid-1", event_type: "messages",
      payload: { "message" => { "mid" => "mid-1" } }, account: account
    }.merge(overrides))
  end

  describe ".claim" do
    it "banks the event verbatim" do
      event = claim

      expect(event).to be_persisted
      expect(event.status).to eq("pending")
      expect(event.received_at).to be_present
      expect(event.payload).to eq("message" => { "mid" => "mid-1" })
    end

    # Meta retries anything it considers unacknowledged, so a duplicate is
    # routine. The unique index is what makes the claim atomic under the
    # concurrent deliveries that produces.
    it "returns nil for an event already delivered" do
      claim

      expect(claim).to be_nil
      expect(described_class.count).to eq(1)
    end

    it "treats the same key under a different field as a different event" do
      claim
      other = claim(field: "message_echoes")

      expect(other).to be_persisted
    end

    it "accepts an event belonging to no account" do
      event = claim(account: nil)

      expect(event.account_id).to be_nil
    end
  end

  describe "state transitions" do
    it "records the row an event produced so it can be traced" do
      conversation = InstagramConnect::Conversation.locate(account: account, igsid: "CUST")
      event = claim

      event.mark_processed!(conversation)

      expect(event.status).to eq("processed")
      expect(event).to be_processed
      expect(event.subject).to eq(conversation)
      expect(event.processed_at).to be_present
    end

    it "marks an event unhandled without a subject" do
      event = claim
      event.mark_unhandled!

      expect(event.status).to eq("unhandled")
      expect(event.subject).to be_nil
    end

    it "keeps the error that failed it, truncated so a huge message cannot bloat the row" do
      event = claim
      event.mark_failed!(ArgumentError.new("x" * 2000))

      expect(event.status).to eq("failed")
      expect(event.error_class).to eq("ArgumentError")
      expect(event.error_message.length).to eq(1000)
    end
  end

  describe "scopes" do
    it "treats pending, unhandled and failed as replayable, but not processed" do
      pending_event = claim(dedupe_key: "a")
      unhandled = claim(dedupe_key: "b").tap(&:mark_unhandled!)
      failed = claim(dedupe_key: "c").tap { |e| e.mark_failed!(StandardError.new("no")) }
      claim(dedupe_key: "d").mark_processed!

      expect(described_class.replayable).to contain_exactly(pending_event, unhandled, failed)
      expect(described_class.pending).to contain_exactly(pending_event)
    end

    it "filters by field and orders by when the event happened, not when it arrived" do
      late = claim(dedupe_key: "late", occurred_at: 1.hour.ago)
      early = claim(dedupe_key: "early", occurred_at: 2.hours.ago)
      claim(dedupe_key: "other", field: "comments")

      expect(described_class.for_field("messages").chronological).to eq([ early, late ])
    end
  end

  it "validates status against the known set" do
    event = claim
    event.status = "nonsense"

    expect(event).not_to be_valid
  end
end

require "rails_helper"

RSpec.describe InstagramConnect::Conversation do
  let(:account) { InstagramConnect::Account.create!(ig_user_id: "IG1", auth_path: "instagram_login", access_token: "t") }

  def message(direction:, body: "hello")
    convo = InstagramConnect::Conversation.locate(account: account, igsid: "CUST")
    InstagramConnect::Message.create!(conversation: convo, direction: direction, status: "received", kind: "dm", body: body)
  end

  describe ".locate" do
    it "creates then finds the same thread for an account + igsid" do
      first = described_class.locate(account: account, igsid: "CUST")
      second = described_class.locate(account: account, igsid: "CUST")
      expect(second).to eq(first)
      expect(described_class.count).to eq(1)
    end

    it "falls back to a lookup if a concurrent insert wins the race" do
      allow(described_class).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordNotUnique)
      existing = described_class.create!(account: account, igsid: "CUST")
      expect(described_class.locate(account: account, igsid: "CUST")).to eq(existing)
    end
  end

  describe "#register_message" do
    it "bumps last_inbound_at and unread_count for an inbound message" do
      convo = described_class.locate(account: account, igsid: "CUST")
      convo.register_message(message(direction: "inbound", body: "hi there"))
      expect(convo.unread_count).to eq(1)
      expect(convo.last_inbound_at).to be_present
      expect(convo.last_message_preview).to eq("hi there")
    end

    it "does not bump unread_count for an outbound message" do
      convo = described_class.locate(account: account, igsid: "CUST")
      convo.register_message(message(direction: "outbound", body: "reply"))
      expect(convo.unread_count).to eq(0)
      expect(convo.last_inbound_at).to be_nil
      expect(convo.last_message_preview).to eq("reply")
    end
  end

  describe "scopes" do
    it ".unread selects threads with unread messages" do
      unread = described_class.create!(account: account, igsid: "A", unread_count: 2)
      described_class.create!(account: account, igsid: "B", unread_count: 0)
      expect(described_class.unread).to contain_exactly(unread)
    end

    it ".recent orders by last_message_at with nulls last" do
      older = described_class.create!(account: account, igsid: "A", last_message_at: 2.days.ago)
      newer = described_class.create!(account: account, igsid: "B", last_message_at: 1.hour.ago)
      never = described_class.create!(account: account, igsid: "C", last_message_at: nil)
      expect(described_class.recent.to_a).to eq([ newer, older, never ])
    end
  end

  it "validates igsid presence and uniqueness within an account" do
    described_class.create!(account: account, igsid: "CUST")
    dup = described_class.new(account: account, igsid: "CUST")
    expect(dup).not_to be_valid
  end
end

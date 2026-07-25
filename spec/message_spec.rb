require "rails_helper"

RSpec.describe InstagramConnect::Message do
  let(:account) { InstagramConnect::Account.create!(ig_user_id: "IG1", auth_path: "instagram_login", access_token: "t") }
  let(:conversation) { InstagramConnect::Conversation.locate(account: account, igsid: "CUST") }

  def build(**attrs)
    described_class.new({ conversation: conversation, direction: "inbound", status: "received", kind: "dm" }.merge(attrs))
  end

  describe "validations" do
    it "accepts a valid message" do
      expect(build(body: "hi")).to be_valid
    end

    it "rejects an unknown direction, status, or kind" do
      expect(build(direction: "sideways")).not_to be_valid
      expect(build(status: "teleported")).not_to be_valid
      expect(build(kind: "smoke_signal")).not_to be_valid
    end
  end

  describe "direction predicates" do
    it "reports inbound and outbound" do
      expect(build(direction: "inbound")).to be_inbound
      expect(build(direction: "outbound")).to be_outbound
      expect(build(direction: "inbound")).not_to be_outbound
    end
  end

  describe "#preview" do
    it "truncates the body when present" do
      expect(build(body: "a" * 200).preview.length).to be <= InstagramConnect::Message::PREVIEW_LIMIT + 3
    end

    it "falls back to the kind when the body is blank" do
      expect(build(body: nil, kind: "story_reply").preview).to eq("[story_reply]")
    end
  end

  describe "scopes" do
    it "separates inbound and outbound and orders chronologically" do
      i = build(direction: "inbound").tap(&:save!)
      o = build(direction: "outbound", status: "sent").tap(&:save!)
      expect(described_class.inbound).to contain_exactly(i)
      expect(described_class.outbound).to contain_exactly(o)
      expect(described_class.chronological.to_a).to eq([ i, o ])
    end
  end

  describe "wire fields" do
    let(:account) do
      InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "t")
    end
    let(:conversation) { InstagramConnect::Conversation.locate(account: account, igsid: "CUST") }

    def build(**attrs)
      conversation.messages.create!(
        { direction: "inbound", status: "received", kind: "dm" }.merge(attrs)
      )
    end

    # Rows written before sent_at existed have only our clock to fall back on.
    it "prefers Meta's clock and falls back to ours" do
      wired = build(sent_at: 2.hours.ago)
      legacy = build(sent_at: nil)

      expect(wired.occurred_at).to eq(wired.sent_at)
      expect(legacy.occurred_at).to eq(legacy.created_at)
    end

    it "reports an unsent message without losing the row" do
      expect(build(deleted_at: Time.current)).to be_deleted
      expect(build).not_to be_deleted
    end

    it "orders a thread by the wire clock, not by insertion" do
      late = build(sent_at: 1.minute.ago, body: "late")
      early = build(sent_at: 1.hour.ago, body: "early")

      expect(conversation.messages.chronological.map(&:body)).to eq(%w[early late])
      expect(late).to be_present
    end

    # Denormalized so account-scoped queries and stream names need no join, and
    # so uniqueness can be scoped per account.
    it "inherits the account from its conversation" do
      expect(build.account_id).to eq(account.id)
    end

    it "keeps an account_id that was set explicitly" do
      expect(build(account_id: 99).account_id).to eq(99)
    end

    it "validates without a conversation rather than raising on the lookup" do
      message = InstagramConnect::Message.new(direction: "inbound", status: "received", kind: "dm")

      expect { message.valid? }.not_to raise_error
      expect(message.account_id).to be_nil
    end

    # The gem never depends on Turbo; a host that renders live overrides this.
    it "offers a no-op broadcast seam for callback-free writes" do
      expect(build.broadcast_refresh).to be_nil
    end
  end
end

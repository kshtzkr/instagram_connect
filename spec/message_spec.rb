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
end

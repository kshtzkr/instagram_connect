require "rails_helper"

RSpec.describe InstagramConnect::Comment do
  let(:account) { InstagramConnect::Account.create!(ig_user_id: "IG1", auth_path: "instagram_login", access_token: "t") }

  describe ".record" do
    it "creates a comment from webhook fields" do
      comment = described_class.record(account: account, comment_id: "c_1", media_id: "m_1", text: "nice", from_username: "fan")
      expect(comment).to be_persisted
      expect(comment.text).to eq("nice")
      expect(comment.from_username).to eq("fan")
    end

    it "upserts an existing comment rather than duplicating it" do
      described_class.record(account: account, comment_id: "c_1", media_id: "m_1", text: "old", from_username: "fan")
      described_class.record(account: account, comment_id: "c_1", media_id: "m_1", text: "edited", from_username: "fan")
      expect(described_class.count).to eq(1)
      expect(described_class.first.text).to eq("edited")
    end
  end

  describe "#hidden? and .visible" do
    it "tracks hidden state" do
      visible = described_class.record(account: account, comment_id: "c_1", media_id: "m", text: "hi", from_username: "a")
      hidden = described_class.record(account: account, comment_id: "c_2", media_id: "m", text: "spam", from_username: "b")
      hidden.update!(hidden_at: Time.current)

      expect(visible).not_to be_hidden
      expect(hidden).to be_hidden
      expect(described_class.visible).to contain_exactly(visible)
    end
  end

  it "requires a unique comment_id" do
    described_class.record(account: account, comment_id: "c_1", media_id: "m", text: "x", from_username: "a")
    dup = described_class.new(account: account, comment_id: "c_1")
    expect(dup).not_to be_valid
  end
end

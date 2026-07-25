require "rails_helper"

RSpec.describe InstagramConnect::MessageReaction do
  let(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "t")
  end
  let(:conversation) { InstagramConnect::Conversation.locate(account: account, igsid: "CUST") }

  def log(action:, at:, reaction: "love")
    described_class.create!(
      conversation: conversation, ig_message_id: "m1", igsid: "CUST",
      actor: "customer", action: action, reaction: reaction, reacted_at: at
    )
  end

  describe ".current_for" do
    # Reading the latest by reacted_at rather than trusting arrival order is
    # what makes Meta's lack of ordering guarantees harmless.
    it "returns the newest reaction by wire time, not by insertion order" do
      newest = log(action: "react", at: 3.minutes.ago)
      log(action: "react", at: 10.minutes.ago, reaction: "like")

      expect(described_class.current_for("m1")).to eq(newest)
    end

    it "returns nil when the last event removed the reaction" do
      log(action: "react", at: 10.minutes.ago)
      log(action: "unreact", at: 1.minute.ago)

      expect(described_class.current_for("m1")).to be_nil
    end

    it "returns nil for a message nobody reacted to" do
      expect(described_class.current_for("never")).to be_nil
    end
  end

  it "reports whether the event added a reaction" do
    expect(log(action: "react", at: Time.current)).to be_react
    expect(log(action: "unreact", at: Time.current)).not_to be_react
  end

  it "rejects an action or actor it does not recognise" do
    reaction = described_class.new(conversation: conversation, ig_message_id: "m1", igsid: "C",
                                   actor: "robot", action: "shrug", reacted_at: Time.current)

    expect(reaction).not_to be_valid
    expect(reaction.errors.attribute_names).to include(:action, :actor)
  end
end

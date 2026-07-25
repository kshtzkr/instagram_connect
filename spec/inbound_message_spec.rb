require "rails_helper"

RSpec.describe InstagramConnect::InboundMessage do
  describe ".claim" do
    it "returns true the first time a message id is seen for an account" do
      expect(described_class.claim(ig_message_id: "m_1", account_id: 1)).to be(true)
    end

    it "returns false for a message id already claimed by that account" do
      described_class.claim(ig_message_id: "m_1", account_id: 1)

      expect(described_class.claim(ig_message_id: "m_1", account_id: 1)).to be(false)
    end

    # Two connected accounts messaging each other share a mid. A global claim
    # would drop the message for whichever account processed second.
    it "lets a second account claim the same message id" do
      described_class.claim(ig_message_id: "m_1", account_id: 1)

      expect(described_class.claim(ig_message_id: "m_1", account_id: 2)).to be(true)
    end
  end
end

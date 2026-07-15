require "rails_helper"

RSpec.describe InstagramConnect::InboundMessage do
  describe ".claim" do
    it "returns true the first time a message id is seen" do
      expect(described_class.claim(ig_message_id: "m_1", account_id: 1)).to be(true)
    end

    it "returns false for an already-claimed message id" do
      described_class.claim(ig_message_id: "m_1")
      expect(described_class.claim(ig_message_id: "m_1")).to be(false)
    end
  end
end

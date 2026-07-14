require "instagram_connect"

RSpec.describe InstagramConnect::Result do
  describe ".ok" do
    it "builds a success result carrying an id and data" do
      result = described_class.ok(id: "mid_123", data: { recipient: "42" })

      expect(result).to be_success
      expect(result).not_to be_failure
      expect(result.id).to eq("mid_123")
      expect(result.data).to eq(recipient: "42")
      expect(result.error_code).to be_nil
    end

    it "defaults data to an empty hash" do
      expect(described_class.ok.data).to eq({})
    end
  end

  describe ".error" do
    it "builds a failure result carrying the error details" do
      result = described_class.error("rate limited", error_code: 613, retry_after: 30)

      expect(result).to be_failure
      expect(result).not_to be_success
      expect(result.error_message).to eq("rate limited")
      expect(result.error_code).to eq(613)
      expect(result.retry_after).to eq(30)
    end
  end

  describe "#initialize" do
    it "coerces a nil data argument to an empty hash" do
      expect(described_class.new(success: true, data: nil).data).to eq({})
    end
  end
end

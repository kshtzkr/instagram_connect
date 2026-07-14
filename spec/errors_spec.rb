require "instagram_connect"

RSpec.describe "InstagramConnect errors" do
  it "roots every error at InstagramConnect::Error" do
    expect(InstagramConnect::ConfigurationError.ancestors).to include(InstagramConnect::Error)
    expect(InstagramConnect::ApiError.ancestors).to include(InstagramConnect::Error)
    expect(InstagramConnect::SignatureError.ancestors).to include(InstagramConnect::Error)
    expect(InstagramConnect::Error.ancestors).to include(StandardError)
  end

  describe InstagramConnect::ApiError do
    it "carries status, error_code, and retry_after alongside the message" do
      error = described_class.new("over rate limit", status: 429, error_code: 4, retry_after: 60)

      expect(error.message).to eq("over rate limit")
      expect(error.status).to eq(429)
      expect(error.error_code).to eq(4)
      expect(error.retry_after).to eq(60)
    end

    it "defaults the metadata to nil when omitted" do
      error = described_class.new("boom")

      expect(error.status).to be_nil
      expect(error.error_code).to be_nil
      expect(error.retry_after).to be_nil
    end
  end
end

require "instagram_connect"

RSpec.describe InstagramConnect::Configuration do
  subject(:config) { described_class.new }

  describe "defaults" do
    it "defaults auth_path to :instagram_login" do
      expect(config.auth_path).to eq(:instagram_login)
    end

    it "pins a Graph API version" do
      expect(config.graph_version).to eq("v21.0")
    end

    it "encrypts tokens by default" do
      expect(config.encrypt_tokens).to be(true)
    end

    it "uses a sensible default page size and media policy" do
      expect(config.default_per_page).to eq(25)
      expect(config.media_max_bytes).to eq(25 * 1024 * 1024)
      expect(config.allowed_media_types).to include("image/jpeg", "video/mp4", "application/pdf")
    end

    it "provides a default current_user_id_resolver that is safe off a plain object" do
      expect(config.current_user_id_resolver.call).to be_nil
    end
  end

  describe "#auth_path=" do
    it "coerces a string to a symbol" do
      config.auth_path = "facebook_login"
      expect(config.auth_path).to eq(:facebook_login)
    end

    it "leaves nil as nil" do
      config.auth_path = nil
      expect(config.auth_path).to be_nil
    end
  end

  describe "#validate!" do
    it "passes for a known auth_path" do
      config.auth_path = :facebook_login
      expect(config.validate!).to be(true)
    end

    it "raises for an unknown auth_path" do
      config.auth_path = :myspace_login
      expect { config.validate! }.to raise_error(InstagramConnect::ConfigurationError, /auth_path must be one of/)
    end
  end
end

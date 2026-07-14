require "instagram_connect"

RSpec.describe InstagramConnect do
  describe "VERSION" do
    it "is a semantic version string" do
      expect(InstagramConnect::VERSION).to match(/\A\d+\.\d+\.\d+/)
    end
  end

  describe ".configuration" do
    it "memoizes a single Configuration instance" do
      expect(described_class.configuration).to be_a(InstagramConnect::Configuration)
      expect(described_class.configuration).to equal(described_class.configuration)
    end
  end

  describe ".configure" do
    it "yields the configuration, validates it, and returns it" do
      returned = described_class.configure do |c|
        c.auth_path = :facebook_login
      end

      expect(returned).to equal(described_class.configuration)
      expect(described_class.configuration.auth_path).to eq(:facebook_login)
    end

    it "raises when the resulting config is invalid" do
      expect do
        described_class.configure { |c| c.auth_path = :nope }
      end.to raise_error(InstagramConnect::ConfigurationError)
    end
  end

  describe ".reset!" do
    it "replaces the configuration with a fresh instance" do
      original = described_class.configuration
      described_class.reset!
      expect(described_class.configuration).not_to equal(original)
    end
  end

  describe ".configuration=" do
    it "allows swapping in a custom configuration" do
      custom = InstagramConnect::Configuration.new
      described_class.configuration = custom
      expect(described_class.configuration).to equal(custom)
    end
  end
end

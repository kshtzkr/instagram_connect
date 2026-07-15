require "instagram_connect"

RSpec.describe InstagramConnect::Doctor do
  def config(**overrides)
    InstagramConnect::Configuration.new.tap do |c|
      c.auth_path = overrides.fetch(:auth_path, :instagram_login)
      c.app_id = overrides.fetch(:app_id, "id")
      c.app_secret = overrides.fetch(:app_secret, "secret")
      c.verify_token = overrides.fetch(:verify_token, "vt")
    end
  end

  it "passes every check when fully configured" do
    expect(described_class.run(config: config).all? { |c| c[:ok] }).to be(true)
  end

  it "flags a missing secret" do
    result = described_class.run(config: config(app_secret: ""))
    expect(result.find { |c| c[:label].include?("app_secret") }[:ok]).to be(false)
  end

  it "flags an unknown auth_path" do
    bad = InstagramConnect::Configuration.new
    bad.auth_path = :bogus
    result = described_class.run(config: bad)
    expect(result.find { |c| c[:label].include?("auth_path") }[:ok]).to be(false)
  end
end

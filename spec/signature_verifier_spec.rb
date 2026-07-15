require "instagram_connect"

RSpec.describe InstagramConnect::SignatureVerifier do
  let(:secret) { "app-secret" }
  let(:body) { '{"object":"instagram","entry":[]}' }

  def sign(payload, key)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', key, payload)}"
  end

  it "accepts a correct signature" do
    expect(described_class.valid?(raw_body: body, signature: sign(body, secret), app_secret: secret)).to be(true)
  end

  it "rejects a signature of a different length" do
    expect(described_class.valid?(raw_body: body, signature: "sha256=deadbeef", app_secret: secret)).to be(false)
  end

  it "rejects a same-length but incorrect signature (tampered body)" do
    expect(described_class.valid?(raw_body: "tampered", signature: sign(body, secret), app_secret: secret)).to be(false)
  end

  it "rejects a blank signature" do
    expect(described_class.valid?(raw_body: body, signature: "", app_secret: secret)).to be(false)
  end

  it "rejects when the app secret is blank" do
    expect(described_class.valid?(raw_body: body, signature: sign(body, secret), app_secret: "")).to be(false)
  end

  it "defaults the app secret to the configured value" do
    InstagramConnect.configure do |c|
      c.auth_path = :instagram_login
      c.app_secret = secret
    end
    expect(described_class.valid?(raw_body: body, signature: sign(body, secret))).to be(true)
  end
end

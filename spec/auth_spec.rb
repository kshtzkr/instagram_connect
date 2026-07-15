require "instagram_connect"

JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

def config_with_credentials(auth_path: :instagram_login)
  InstagramConnect::Configuration.new.tap do |c|
    c.auth_path = auth_path
    c.app_id = "APPID"
    c.app_secret = "SECRET"
  end
end

RSpec.describe InstagramConnect::Auth::Strategy do
  let(:config) { config_with_credentials }
  subject(:strategy) { described_class.new(config) }

  it "raises NotImplementedError for every abstract method" do
    expect { strategy.graph_host }.to raise_error(NotImplementedError)
    expect { strategy.scopes }.to raise_error(NotImplementedError)
    expect { strategy.authorize_url(redirect_uri: "x", state: "y") }.to raise_error(NotImplementedError)
    expect { strategy.exchange_code(code: "c", redirect_uri: "r") }.to raise_error(NotImplementedError)
    expect { strategy.refresh_token(access_token: "t") }.to raise_error(NotImplementedError)
  end

  describe "credential accessors" do
    it "returns present credentials and graph version" do
      expect(strategy.send(:app_id)).to eq("APPID")
      expect(strategy.send(:app_secret)).to eq("SECRET")
      expect(strategy.send(:graph_version)).to eq("v21.0")
    end

    it "raises when app_id is blank" do
      config.app_id = nil
      expect { strategy.send(:app_id) }.to raise_error(InstagramConnect::ConfigurationError, /app_id/)
    end

    it "raises when app_secret is blank" do
      config.app_secret = ""
      expect { strategy.send(:app_secret) }.to raise_error(InstagramConnect::ConfigurationError, /app_secret/)
    end
  end

  it "computes expires_at from a seconds value or nil" do
    expect(strategy.send(:expires_at_from, nil)).to be_nil
    expect(strategy.send(:expires_at_from, 100)).to be_within(5).of(Time.now + 100)
  end
end

RSpec.describe InstagramConnect::Auth::InstagramLogin do
  let(:config) { config_with_credentials(auth_path: :instagram_login) }
  subject(:strategy) { described_class.new(config) }

  it "reports its graph host and scopes" do
    expect(strategy.graph_host).to eq("https://graph.instagram.com")
    expect(strategy.scopes).to include("instagram_business_manage_messages")
  end

  it "builds an authorize URL" do
    url = strategy.authorize_url(redirect_uri: "https://app.test/cb", state: "abc")
    expect(url).to start_with("https://www.instagram.com/oauth/authorize?")
    expect(url).to include("client_id=APPID").and include("state=abc").and include("response_type=code")
  end

  describe "#exchange_code" do
    it "exchanges a code for a long-lived token and ig_user_id" do
      stub_request(:post, "https://api.instagram.com/oauth/access_token")
        .to_return(status: 200, body: { access_token: "short", user_id: 12_345 }.to_json, headers: JSON_HEADERS)
      stub_request(:get, "https://graph.instagram.com/access_token")
        .with(query: hash_including("grant_type" => "ig_exchange_token"))
        .to_return(status: 200, body: { access_token: "long", expires_in: 5_184_000 }.to_json, headers: JSON_HEADERS)

      result = strategy.exchange_code(code: "code", redirect_uri: "https://app.test/cb")

      expect(result[:access_token]).to eq("long")
      expect(result[:ig_user_id]).to eq("12345")
      expect(result[:expires_at]).to be_within(60).of(Time.now + 5_184_000)
    end

    it "returns a nil ig_user_id when the short exchange omits user_id" do
      stub_request(:post, "https://api.instagram.com/oauth/access_token")
        .to_return(status: 200, body: { access_token: "short" }.to_json, headers: JSON_HEADERS)
      stub_request(:get, "https://graph.instagram.com/access_token")
        .with(query: hash_including("grant_type" => "ig_exchange_token"))
        .to_return(status: 200, body: { access_token: "long", expires_in: 5_184_000 }.to_json, headers: JSON_HEADERS)

      expect(strategy.exchange_code(code: "c", redirect_uri: "r")[:ig_user_id]).to be_nil
    end

    it "raises when the short-lived exchange fails" do
      stub_request(:post, "https://api.instagram.com/oauth/access_token").to_return(status: 400, body: "{}", headers: JSON_HEADERS)
      expect { strategy.exchange_code(code: "c", redirect_uri: "r") }
        .to raise_error(InstagramConnect::ApiError, /code exchange failed/)
    end

    it "raises when the long-lived exchange fails" do
      stub_request(:post, "https://api.instagram.com/oauth/access_token")
        .to_return(status: 200, body: { access_token: "short" }.to_json, headers: JSON_HEADERS)
      stub_request(:get, "https://graph.instagram.com/access_token")
        .with(query: hash_including("grant_type" => "ig_exchange_token"))
        .to_return(status: 500, body: "{}", headers: JSON_HEADERS)
      expect { strategy.exchange_code(code: "c", redirect_uri: "r") }
        .to raise_error(InstagramConnect::ApiError, /long-lived/)
    end
  end

  describe "#refresh_token" do
    it "refreshes and returns the rotated token" do
      stub_request(:get, "https://graph.instagram.com/refresh_access_token")
        .with(query: hash_including("grant_type" => "ig_refresh_token"))
        .to_return(status: 200, body: { access_token: "fresh", expires_in: 5_184_000 }.to_json, headers: JSON_HEADERS)

      result = strategy.refresh_token(access_token: "old")

      expect(result[:access_token]).to eq("fresh")
      expect(result[:expires_at]).to be_within(60).of(Time.now + 5_184_000)
    end

    it "raises on refresh failure" do
      stub_request(:get, "https://graph.instagram.com/refresh_access_token")
        .with(query: hash_including("grant_type" => "ig_refresh_token"))
        .to_return(status: 400, body: "{}", headers: JSON_HEADERS)
      expect { strategy.refresh_token(access_token: "old") }.to raise_error(InstagramConnect::ApiError, /refresh/)
    end
  end
end

RSpec.describe InstagramConnect::Auth::FacebookLogin do
  let(:config) { config_with_credentials(auth_path: :facebook_login) }
  subject(:strategy) { described_class.new(config) }

  it "reports its graph host and scopes" do
    expect(strategy.graph_host).to eq("https://graph.facebook.com")
    expect(strategy.scopes).to include("instagram_manage_messages").and include("pages_manage_metadata")
  end

  it "builds an authorize URL on the FB dialog" do
    url = strategy.authorize_url(redirect_uri: "https://app.test/cb", state: "s")
    expect(url).to start_with("https://www.facebook.com/v21.0/dialog/oauth?")
    expect(url).to include("client_id=APPID")
  end

  describe "#exchange_code" do
    it "exchanges code -> short -> long-lived token" do
      stub_request(:get, "https://graph.facebook.com/v21.0/oauth/access_token")
        .with(query: hash_including("code" => "code"))
        .to_return(status: 200, body: { access_token: "short" }.to_json, headers: JSON_HEADERS)
      stub_request(:get, "https://graph.facebook.com/v21.0/oauth/access_token")
        .with(query: hash_including("grant_type" => "fb_exchange_token"))
        .to_return(status: 200, body: { access_token: "long", expires_in: 5_184_000 }.to_json, headers: JSON_HEADERS)

      result = strategy.exchange_code(code: "code", redirect_uri: "https://app.test/cb")

      expect(result[:access_token]).to eq("long")
      expect(result[:expires_at]).to be_within(60).of(Time.now + 5_184_000)
    end

    it "raises on short exchange failure" do
      stub_request(:get, "https://graph.facebook.com/v21.0/oauth/access_token")
        .with(query: hash_including("code" => "bad")).to_return(status: 400, body: "{}", headers: JSON_HEADERS)
      expect { strategy.exchange_code(code: "bad", redirect_uri: "r") }
        .to raise_error(InstagramConnect::ApiError, /code exchange/)
    end

    it "raises on long exchange failure" do
      stub_request(:get, "https://graph.facebook.com/v21.0/oauth/access_token")
        .with(query: hash_including("code" => "code")).to_return(status: 200, body: { access_token: "short" }.to_json, headers: JSON_HEADERS)
      stub_request(:get, "https://graph.facebook.com/v21.0/oauth/access_token")
        .with(query: hash_including("grant_type" => "fb_exchange_token")).to_return(status: 500, body: "{}", headers: JSON_HEADERS)
      expect { strategy.exchange_code(code: "code", redirect_uri: "r") }
        .to raise_error(InstagramConnect::ApiError, /long-lived/)
    end
  end

  it "treats refresh as a no-op returning the token unchanged" do
    expect(strategy.refresh_token(access_token: "durable")).to eq(access_token: "durable", expires_at: nil)
  end
end

RSpec.describe InstagramConnect::Auth do
  it "returns the InstagramLogin strategy for :instagram_login" do
    expect(described_class.for(config_with_credentials(auth_path: :instagram_login)))
      .to be_a(InstagramConnect::Auth::InstagramLogin)
  end

  it "returns the FacebookLogin strategy for :facebook_login" do
    expect(described_class.for(config_with_credentials(auth_path: :facebook_login)))
      .to be_a(InstagramConnect::Auth::FacebookLogin)
  end

  it "raises for an unknown auth_path" do
    config = InstagramConnect::Configuration.new
    config.auth_path = :bogus
    expect { described_class.for(config) }.to raise_error(InstagramConnect::ConfigurationError, /unknown auth_path/)
  end
end

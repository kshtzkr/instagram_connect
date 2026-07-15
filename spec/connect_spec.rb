require "rails_helper"

RSpec.describe InstagramConnect::Connect do
  let(:json) { { "Content-Type" => "application/json" } }

  def config(auth_path:)
    InstagramConnect::Configuration.new.tap do |c|
      c.auth_path = auth_path
      c.app_id = "APPID"
      c.app_secret = "SECRET"
    end
  end

  describe "Instagram-Login path" do
    before do
      stub_request(:post, "https://api.instagram.com/oauth/access_token")
        .to_return(status: 200, body: { access_token: "short", user_id: 999 }.to_json, headers: json)
      stub_request(:get, "https://graph.instagram.com/access_token")
        .with(query: hash_including("grant_type" => "ig_exchange_token"))
        .to_return(status: 200, body: { access_token: "long", expires_in: 5_184_000 }.to_json, headers: json)
    end

    it "creates an account from the exchanged token" do
      account = described_class.call(code: "code", redirect_uri: "https://app.test/cb", config: config(auth_path: :instagram_login))

      expect(account).to be_persisted
      expect(account.ig_user_id).to eq("999")
      expect(account.access_token).to eq("long")
      expect(account.auth_path).to eq("instagram_login")
      expect(account).to be_active
    end

    it "records the connecting user when given" do
      account = described_class.call(code: "c", redirect_uri: "r", config: config(auth_path: :instagram_login), connected_by_id: 7)
      expect(account.connected_by_id).to eq(7)
    end

    it "updates an existing account rather than duplicating it" do
      InstagramConnect::Account.create!(ig_user_id: "999", auth_path: "instagram_login", access_token: "stale")

      account = described_class.call(code: "c", redirect_uri: "r", config: config(auth_path: :instagram_login))

      expect(InstagramConnect::Account.count).to eq(1)
      expect(account.access_token).to eq("long")
    end
  end

  describe "Facebook-Login path" do
    before do
      stub_request(:get, "https://graph.facebook.com/v21.0/oauth/access_token")
        .with(query: hash_including("code" => "code"))
        .to_return(status: 200, body: { access_token: "short" }.to_json, headers: json)
      stub_request(:get, "https://graph.facebook.com/v21.0/oauth/access_token")
        .with(query: hash_including("grant_type" => "fb_exchange_token"))
        .to_return(status: 200, body: { access_token: "long", expires_in: 5_184_000 }.to_json, headers: json)
    end

    it "resolves the IG business account via the linked Page" do
      stub_request(:get, "https://graph.facebook.com/v21.0/me/accounts")
        .with(query: hash_including({}))
        .to_return(status: 200, body: {
          data: [ { id: "PAGE1", instagram_business_account: { id: "IGBIZ1" } } ]
        }.to_json, headers: json)

      account = described_class.call(code: "code", redirect_uri: "r", config: config(auth_path: :facebook_login))

      expect(account.ig_user_id).to eq("IGBIZ1")
      expect(account.page_id).to eq("PAGE1")
    end

    it "raises when no Page has a linked IG business account" do
      stub_request(:get, "https://graph.facebook.com/v21.0/me/accounts")
        .with(query: hash_including({}))
        .to_return(status: 200, body: { data: [ { id: "PAGE1" } ] }.to_json, headers: json)

      expect { described_class.call(code: "code", redirect_uri: "r", config: config(auth_path: :facebook_login)) }
        .to raise_error(InstagramConnect::ConfigurationError, /no Instagram business account/)
    end
  end
end

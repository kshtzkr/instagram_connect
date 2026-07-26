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

    # /me/accounts lists only the Pages a token may enumerate. A Page granted
    # through the Login-for-Business asset picker is absent from it while reading
    # fine by id — the listing comes back EMPTY and the account is still there.
    it "falls back to the assets the token was granted when the listing is empty" do
      stub_request(:get, "https://graph.facebook.com/v21.0/me/accounts")
        .with(query: hash_including({}))
        .to_return(status: 200, body: { data: [] }.to_json, headers: json)
      stub_request(:get, "https://graph.facebook.com/v21.0/debug_token")
        .with(query: hash_including({}))
        .to_return(status: 200, body: {
          data: { granular_scopes: [ { scope: "pages_show_list", target_ids: [ "PAGE9" ] } ] }
        }.to_json, headers: json)
      stub_request(:get, "https://graph.facebook.com/v21.0/PAGE9")
        .with(query: hash_including({}))
        .to_return(status: 200, body: {
          id: "PAGE9", instagram_business_account: { id: "IGBIZ9" }
        }.to_json, headers: json)

      account = described_class.call(code: "code", redirect_uri: "r", config: config(auth_path: :facebook_login))

      expect(account.ig_user_id).to eq("IGBIZ9")
      expect(account.page_id).to eq("PAGE9")
    end

    it "ignores a granted asset that is not a Page with an Instagram account" do
      stub_request(:get, "https://graph.facebook.com/v21.0/me/accounts")
        .with(query: hash_including({}))
        .to_return(status: 200, body: { data: [] }.to_json, headers: json)
      stub_request(:get, "https://graph.facebook.com/v21.0/debug_token")
        .with(query: hash_including({}))
        .to_return(status: 200, body: {
          data: { granular_scopes: [ { scope: "pages_show_list", target_ids: [ "NOPE" ] } ] }
        }.to_json, headers: json)
      stub_request(:get, "https://graph.facebook.com/v21.0/NOPE")
        .with(query: hash_including({}))
        .to_return(status: 404, body: { error: { message: "gone" } }.to_json, headers: json)

      expect { described_class.call(code: "code", redirect_uri: "r", config: config(auth_path: :facebook_login)) }
        .to raise_error(InstagramConnect::ConfigurationError, /no Page with a linked Instagram/)
    end

    it "says so plainly when neither the listing nor the grants yield a Page" do
      stub_request(:get, "https://graph.facebook.com/v21.0/me/accounts")
        .with(query: hash_including({}))
        .to_return(status: 200, body: { data: [ { id: "PAGE1" } ] }.to_json, headers: json)
      stub_request(:get, "https://graph.facebook.com/v21.0/debug_token")
        .with(query: hash_including({}))
        .to_return(status: 200, body: { data: {} }.to_json, headers: json)

      expect { described_class.call(code: "code", redirect_uri: "r", config: config(auth_path: :facebook_login)) }
        .to raise_error(InstagramConnect::ConfigurationError, /no Page with a linked Instagram/)
    end

    # A debug_token that itself fails must not crash the connect — it just means
    # this fallback has nothing to offer, and the error below is still accurate.
    it "survives the grant lookup failing" do
      stub_request(:get, "https://graph.facebook.com/v21.0/me/accounts")
        .with(query: hash_including({}))
        .to_return(status: 200, body: { data: [] }.to_json, headers: json)
      stub_request(:get, "https://graph.facebook.com/v21.0/debug_token")
        .with(query: hash_including({}))
        .to_return(status: 400, body: { error: { message: "bad app token" } }.to_json, headers: json)

      expect { described_class.call(code: "code", redirect_uri: "r", config: config(auth_path: :facebook_login)) }
        .to raise_error(InstagramConnect::ConfigurationError, /no Page with a linked Instagram/)
    end

    # A failed call and an empty list are different facts. Reporting the first as
    # the second sent an operator hunting a Page link that was never broken.
    it "reports an API failure as a failure, not as a missing account" do
      stub_request(:get, "https://graph.facebook.com/v21.0/me/accounts")
        .with(query: hash_including({}))
        .to_return(status: 400, body: { error: { message: "Invalid OAuth token", code: 190 } }.to_json,
                   headers: json)

      expect { described_class.call(code: "code", redirect_uri: "r", config: config(auth_path: :facebook_login)) }
        .to raise_error(InstagramConnect::ApiError, /Invalid OAuth token/)
    end
  end
end

require "rails_helper"

RSpec.describe "OAuth connect", type: :request do
  def state_from(location)
    Rack::Utils.parse_query(URI(location).query)["state"]
  end

  def start_and_capture_state
    get "/instagram/oauth/start"
    state_from(response.location)
  end

  describe "GET /instagram/oauth/start" do
    it "redirects to the Instagram authorize dialog with a state" do
      get "/instagram/oauth/start"
      expect(response).to have_http_status(:redirect)
      expect(response.location).to start_with("https://www.instagram.com/oauth/authorize")
      expect(state_from(response.location)).to be_present
    end

    it "uses a configured redirect_uri when present" do
      InstagramConnect.configuration.redirect_uri = "https://host.test/ig/callback"
      get "/instagram/oauth/start"
      expect(response.location).to include("host.test")
    end
  end

  describe "GET /instagram/oauth/callback" do
    it "exchanges the code and connects the account" do
      stub_request(:post, "https://api.instagram.com/oauth/access_token")
        .to_return(status: 200, body: { access_token: "short", user_id: 999 }.to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, "https://graph.instagram.com/access_token")
        .with(query: hash_including("grant_type" => "ig_exchange_token"))
        .to_return(status: 200, body: { access_token: "long", expires_in: 5_184_000 }.to_json,
                   headers: { "Content-Type" => "application/json" })

      state = start_and_capture_state
      get "/instagram/oauth/callback", params: { code: "abc", state: state }

      expect(response).to redirect_to("/")
      expect(InstagramConnect::Account.find_by(ig_user_id: "999")).to be_present
    end

    it "redirects with an alert when Instagram declines" do
      get "/instagram/oauth/callback", params: { error: "access_denied" }
      expect(response).to redirect_to("/")
    end

    it "redirects with an alert on a state mismatch" do
      start_and_capture_state
      get "/instagram/oauth/callback", params: { code: "abc", state: "tampered" }
      expect(response).to redirect_to("/")
    end

    it "redirects with an alert when the token exchange fails" do
      stub_request(:post, "https://api.instagram.com/oauth/access_token")
        .to_return(status: 400, body: "{}", headers: { "Content-Type" => "application/json" })

      state = start_and_capture_state
      get "/instagram/oauth/callback", params: { code: "abc", state: state }
      expect(response).to redirect_to("/")
    end
  end
end

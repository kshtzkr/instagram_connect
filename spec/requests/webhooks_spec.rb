require "rails_helper"

RSpec.describe "Webhooks", type: :request do
  def sign(body)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 'SECRET', body)}"
  end

  describe "GET /instagram/webhooks (verify handshake)" do
    it "echoes the challenge when mode and verify_token match" do
      get "/instagram/webhooks", params: {
        "hub.mode" => "subscribe", "hub.verify_token" => "VERIFY", "hub.challenge" => "12345"
      }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("12345")
    end

    it "forbids a wrong verify_token" do
      get "/instagram/webhooks", params: { "hub.mode" => "subscribe", "hub.verify_token" => "WRONG" }
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids a non-subscribe mode" do
      get "/instagram/webhooks", params: { "hub.mode" => "unsubscribe", "hub.verify_token" => "VERIFY" }
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids when no verify_token is configured" do
      InstagramConnect.configuration.verify_token = ""
      get "/instagram/webhooks", params: { "hub.mode" => "subscribe", "hub.verify_token" => "" }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /instagram/webhooks (event delivery)" do
    let(:body) { { object: "instagram", entry: [] }.to_json }

    it "enqueues ingestion for a correctly signed payload" do
      post "/instagram/webhooks", params: body,
           headers: { "X-Hub-Signature-256" => sign(body), "Content-Type" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(InstagramConnect::IngestJob).to have_been_enqueued
    end

    it "rejects a bad signature" do
      post "/instagram/webhooks", params: body,
           headers: { "X-Hub-Signature-256" => "sha256=bad", "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns bad_request for unparseable JSON under a valid signature" do
      bad = "not json"
      post "/instagram/webhooks", params: bad,
           headers: { "X-Hub-Signature-256" => sign(bad), "Content-Type" => "application/json" }
      expect(response).to have_http_status(:bad_request)
    end
  end
end

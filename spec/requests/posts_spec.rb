require "rails_helper"

RSpec.describe "Posts (publishing)", type: :request do
  let(:base) { "https://graph.instagram.com/v21.0" }
  let(:json) { { "Content-Type" => "application/json" } }

  def account
    InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "TOK")
  end

  describe "GET /instagram/posts" do
    it "redirects to the inbox when no account is connected" do
      get "/instagram/posts"
      expect(response).to redirect_to("/instagram/conversations")
    end

    it "lists media and the publishing quota" do
      account
      stub_request(:get, "#{base}/IGACC/media").with(query: hash_including({}))
        .to_return(status: 200, body: { data: [ { id: "m1", caption: "sunset", permalink: "https://ig/p/1" } ] }.to_json, headers: json)
      stub_request(:get, "#{base}/IGACC/content_publishing_limit").with(query: hash_including({}))
        .to_return(status: 200, body: { data: [ { quota_usage: 3 } ] }.to_json, headers: json)

      get "/instagram/posts"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("sunset")
      expect(response.body).to include("3 / 100")
    end
  end

  describe "GET /instagram/posts/new" do
    it "shows the publish form" do
      account
      get "/instagram/posts/new"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Publish a post")
    end
  end

  describe "POST /instagram/posts" do
    before { account }

    it "publishes an image post" do
      stub_request(:post, "#{base}/IGACC/media").to_return(status: 200, body: { id: "cont1" }.to_json, headers: json)
      stub_request(:post, "#{base}/IGACC/media_publish").to_return(status: 200, body: { id: "post1" }.to_json, headers: json)

      post "/instagram/posts", params: { image_url: "https://cdn.test/x.jpg", caption: "hi" }

      expect(response).to redirect_to("/instagram/posts")
    end

    it "alerts when container creation fails" do
      stub_request(:post, "#{base}/IGACC/media")
        .to_return(status: 400, body: { error: { message: "bad url" } }.to_json, headers: json)

      post "/instagram/posts", params: { image_url: "nope" }

      expect(response).to redirect_to("/instagram/posts/new")
    end

    it "alerts when publishing fails" do
      stub_request(:post, "#{base}/IGACC/media").to_return(status: 200, body: { id: "cont1" }.to_json, headers: json)
      stub_request(:post, "#{base}/IGACC/media_publish")
        .to_return(status: 400, body: { error: { message: "over limit" } }.to_json, headers: json)

      post "/instagram/posts", params: { image_url: "https://cdn.test/x.jpg" }

      expect(response).to redirect_to("/instagram/posts/new")
    end
  end
end

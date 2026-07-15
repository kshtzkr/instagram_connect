require "rails_helper"

RSpec.describe "Comments moderation", type: :request do
  let(:account) { InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "TOK") }
  let(:base) { "https://graph.instagram.com/v21.0" }
  let(:json) { { "Content-Type" => "application/json" } }

  def comment(id: "c1", **attrs)
    c = InstagramConnect::Comment.record(account: account, comment_id: id, media_id: "m1", text: "hi", from_username: "fan")
    c.update!(attrs) if attrs.any?
    c
  end

  describe "GET /instagram/comments" do
    it "lists captured comments" do
      comment(id: "c1")
      get "/instagram/comments"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("fan")
    end

    it "renders an empty state and honors the page param" do
      get "/instagram/comments", params: { page: 2 }
      expect(response.body).to include("No comments captured")
    end
  end

  describe "moderation actions" do
    it "replies to a comment" do
      c = comment
      req = stub_request(:post, "#{base}/c1/replies").to_return(status: 200, body: { id: "r1" }.to_json, headers: json)

      post "/instagram/comments/#{c.id}/reply", params: { text: "thanks!" }

      expect(response).to redirect_to("/instagram/comments")
      expect(c.reload.replied_at).to be_present
      expect(req).to have_been_requested
    end

    it "hides a comment" do
      c = comment
      stub_request(:post, "#{base}/c1").to_return(status: 200, body: { success: true }.to_json, headers: json)

      post "/instagram/comments/#{c.id}/hide"

      expect(c.reload.hidden_at).to be_present
    end

    it "unhides a comment" do
      c = comment(hidden_at: Time.current)
      stub_request(:post, "#{base}/c1").to_return(status: 200, body: { success: true }.to_json, headers: json)

      post "/instagram/comments/#{c.id}/unhide"

      expect(c.reload.hidden_at).to be_nil
    end

    it "deletes a comment" do
      c = comment
      stub_request(:delete, "#{base}/c1").to_return(status: 200, body: { success: true }.to_json, headers: json)

      delete "/instagram/comments/#{c.id}"

      expect(InstagramConnect::Comment.exists?(c.id)).to be(false)
    end

    it "leaves local state unchanged and alerts when the API call fails" do
      c = comment
      stub_request(:post, "#{base}/c1/replies").to_return(status: 400, body: { error: { message: "nope" } }.to_json, headers: json)

      post "/instagram/comments/#{c.id}/reply", params: { text: "hi" }

      expect(response).to redirect_to("/instagram/comments")
      expect(c.reload.replied_at).to be_nil
    end
  end
end

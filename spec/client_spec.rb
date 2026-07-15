require "instagram_connect"

RSpec.describe InstagramConnect::Client do
  let(:config) do
    InstagramConnect::Configuration.new.tap do |c|
      c.auth_path = :instagram_login
      c.app_id = "APPID"
      c.app_secret = "SECRET"
    end
  end
  let(:client) { described_class.new(access_token: "TOK", config: config, ig_user_id: "IGID") }
  let(:base) { "https://graph.instagram.com/v21.0" }
  let(:json) { { "Content-Type" => "application/json" } }

  def stub_ok(method, path, body:, query: {})
    stub_request(method, "#{base}#{path}")
      .with(query: hash_including(query))
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "direct messages" do
    it "sends text and returns the message id" do
      stub_ok(:post, "/me/messages", body: { message_id: "mid_1" })
      result = client.send_text(recipient_id: "42", text: "hi")
      expect(result).to be_success
      expect(result.id).to eq("mid_1")
    end

    it "sends text with a HUMAN_AGENT tag" do
      req = stub_request(:post, "#{base}/me/messages")
        .with(body: hash_including("tag" => "HUMAN_AGENT", "messaging_type" => "MESSAGE_TAG"))
        .to_return(status: 200, body: { message_id: "mid_2" }.to_json, headers: json)
      client.send_text(recipient_id: "42", text: "still here", tag: "HUMAN_AGENT")
      expect(req).to have_been_requested
    end

    it "sends media" do
      req = stub_request(:post, "#{base}/me/messages")
        .with(body: hash_including("message" => hash_including("attachment" => hash_including("type" => "image"))))
        .to_return(status: 200, body: { message_id: "mid_3" }.to_json, headers: json)
      expect(client.send_media(recipient_id: "42", url: "https://cdn/x.jpg")).to be_success
      expect(req).to have_been_requested
    end

    it "sends a reaction" do
      stub_ok(:post, "/me/messages", body: { success: true })
      expect(client.send_reaction(recipient_id: "42", message_id: "mid")).to be_success
    end

    it "sends a private reply to a comment" do
      req = stub_request(:post, "#{base}/me/messages")
        .with(body: hash_including("recipient" => hash_including("comment_id" => "c_1")))
        .to_return(status: 200, body: { message_id: "mid_4" }.to_json, headers: json)
      expect(client.private_reply(comment_id: "c_1", text: "dm")).to be_success
      expect(req).to have_been_requested
    end
  end

  describe "comments" do
    it "replies to a comment" do
      stub_ok(:post, "/c_1/replies", body: { id: "reply_1" })
      expect(client.reply_comment(comment_id: "c_1", text: "thanks").id).to eq("reply_1")
    end

    it "hides a comment" do
      stub_ok(:post, "/c_1", body: { success: true })
      expect(client.hide_comment(comment_id: "c_1")).to be_success
    end

    it "deletes a comment" do
      stub_request(:delete, "#{base}/c_1").to_return(status: 200, body: { success: true }.to_json, headers: json)
      expect(client.delete_comment(comment_id: "c_1")).to be_success
    end

    it "lists comments on a media object" do
      stub_ok(:get, "/m_1/comments", body: { data: [ { id: "c_1" } ] })
      expect(client.list_comments(media_id: "m_1").data["data"]).to eq([ { "id" => "c_1" } ])
    end
  end

  describe "publishing" do
    it "creates a media container" do
      stub_ok(:post, "/IGID/media", body: { id: "container_1" })
      expect(client.create_media_container(image_url: "https://cdn/x.jpg").id).to eq("container_1")
    end

    it "publishes a container" do
      stub_ok(:post, "/IGID/media_publish", body: { id: "post_1" })
      expect(client.publish_media(creation_id: "container_1").id).to eq("post_1")
    end

    it "reads container status" do
      stub_ok(:get, "/container_1", body: { status_code: "FINISHED" })
      expect(client.container_status(container_id: "container_1").data["status_code"]).to eq("FINISHED")
    end

    it "reads the publishing limit" do
      stub_ok(:get, "/IGID/content_publishing_limit", body: { data: [ { quota_usage: 3 } ] })
      expect(client.publishing_limit).to be_success
    end

    it "raises when no ig_user_id is available" do
      no_id = described_class.new(access_token: "TOK", config: config)
      expect { no_id.publish_media(creation_id: "x") }.to raise_error(InstagramConnect::ConfigurationError, /ig_user_id/)
    end
  end

  describe "reads" do
    it "lists media" do
      stub_ok(:get, "/IGID/media", body: { data: [ { id: "m_1" } ] })
      expect(client.list_media.data["data"]).to eq([ { "id" => "m_1" } ])
    end

    it "reads media insights" do
      stub_ok(:get, "/m_1/insights", body: { data: [ { name: "reach" } ] })
      expect(client.media_insights(media_id: "m_1")).to be_success
    end

    it "reads a user profile" do
      stub_ok(:get, "/igsid_1", body: { name: "Ann", username: "ann" })
      expect(client.profile(igsid: "igsid_1").data["username"]).to eq("ann")
    end

    it "lists pages" do
      stub_ok(:get, "/me/accounts", body: { data: [ { id: "page_1" } ] })
      expect(client.list_pages).to be_success
    end
  end

  describe "#fetch_media_binary" do
    it "returns the bytes, mime, and size on success" do
      stub_request(:get, "https://cdn.test/a.jpg")
        .to_return(status: 200, body: "BINARY", headers: { "Content-Type" => "image/jpeg" })
      result = client.fetch_media_binary(url: "https://cdn.test/a.jpg")
      expect(result).to be_success
      expect(result.data[:body]).to eq("BINARY")
      expect(result.data[:mime]).to eq("image/jpeg")
      expect(result.data[:size]).to eq(6)
    end

    it "returns a failure Result when the fetch fails" do
      stub_request(:get, "https://cdn.test/missing.jpg").to_return(status: 404, body: "")
      result = client.fetch_media_binary(url: "https://cdn.test/missing.jpg")
      expect(result).to be_failure
      expect(result.error_code).to eq(404)
    end
  end

  describe "response parsing" do
    it "maps a Graph error body to a failure Result" do
      stub_request(:post, "#{base}/me/messages").to_return(
        status: 400,
        body: { error: { message: "rate limited", code: 613, error_data: { retry_after: 42 } } }.to_json,
        headers: json
      )
      result = client.send_text(recipient_id: "42", text: "hi")
      expect(result).to be_failure
      expect(result.error_message).to eq("rate limited")
      expect(result.error_code).to eq(613)
      expect(result.retry_after).to eq(42)
    end

    it "falls back to an HTTP status message when the error body has no error object" do
      stub_request(:post, "#{base}/me/messages").to_return(status: 500, body: "{}", headers: json)
      result = client.send_text(recipient_id: "42", text: "hi")
      expect(result).to be_failure
      expect(result.error_message).to eq("HTTP 500")
    end

    it "tolerates a non-hash response body" do
      stub_request(:delete, "#{base}/c_9").to_return(status: 200, body: "true", headers: { "Content-Type" => "text/plain" })
      result = client.delete_comment(comment_id: "c_9")
      expect(result).to be_success
      expect(result.id).to be_nil
    end
  end
end

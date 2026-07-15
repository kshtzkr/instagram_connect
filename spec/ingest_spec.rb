require "rails_helper"

RSpec.describe InstagramConnect::Ingest do
  let(:seen_messages) { [] }
  let(:seen_comments) { [] }
  let(:seen_postbacks) { [] }

  let(:config) do
    InstagramConnect::Configuration.new.tap do |c|
      c.auth_path = :instagram_login
      c.on_message = ->(m) { seen_messages << m }
      c.on_comment = ->(comment) { seen_comments << comment }
      c.on_postback = ->(p) { seen_postbacks << p }
    end
  end

  let!(:account) { InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "t") }

  def dm_payload(mid:, sender:, recipient:, text: "hi", echo: false, attachments: nil, entry_id: "IGACC")
    msg = { "mid" => mid }
    msg["text"] = text if text
    msg["is_echo"] = true if echo
    msg["attachments"] = attachments if attachments
    { "entry" => [ { "id" => entry_id, "messaging" => [ { "sender" => { "id" => sender }, "recipient" => { "id" => recipient }, "message" => msg } ] } ] }
  end

  def comment_payload(id: "c1", field: "comments")
    value = { "id" => id, "text" => "nice", "from" => { "username" => "fan" }, "media" => { "id" => "media1" } }
    { "entry" => [ { "id" => "IGACC", "changes" => [ { "field" => field, "value" => value } ] } ] }
  end

  def run(payload)
    described_class.call(payload: payload, config: config)
  end

  describe "direct messages" do
    it "persists an inbound message, bumps the thread, and fires on_message" do
      summary = run(dm_payload(mid: "m1", sender: "CUST", recipient: "IGACC"))

      expect(summary[:messages]).to eq(1)
      convo = InstagramConnect::Conversation.find_by(igsid: "CUST")
      expect(convo.unread_count).to eq(1)
      message = convo.messages.first
      expect(message).to be_inbound
      expect(message.body).to eq("hi")
      expect(seen_messages).to contain_exactly(message)
    end

    it "records an echo of the operator's own reply as outbound without firing on_message" do
      run(dm_payload(mid: "e1", sender: "IGACC", recipient: "CUST", text: "reply", echo: true))

      message = InstagramConnect::Message.first
      expect(message).to be_outbound
      expect(message.source).to eq("operator_app")
      expect(seen_messages).to be_empty
    end

    it "marks messages with attachments as pending media" do
      run(dm_payload(mid: "m2", sender: "CUST", recipient: "IGACC", text: nil, attachments: [ { "type" => "image" } ]))
      expect(InstagramConnect::Message.first.media_status).to eq("pending")
    end

    it "skips a duplicate message id" do
      payload = dm_payload(mid: "dup", sender: "CUST", recipient: "IGACC")
      run(payload)
      summary = run(payload)
      expect(summary[:skipped]).to eq(1)
      expect(InstagramConnect::Message.count).to eq(1)
    end

    it "skips a message with a blank id" do
      summary = run(dm_payload(mid: "", sender: "CUST", recipient: "IGACC"))
      expect(summary).to include(messages: 0, skipped: 1)
    end
  end

  describe "comments" do
    it "upserts a comment and fires on_comment" do
      summary = run(comment_payload(id: "c1"))
      expect(summary[:comments]).to eq(1)
      expect(InstagramConnect::Comment.find_by(comment_id: "c1").text).to eq("nice")
      expect(seen_comments.size).to eq(1)
    end

    it "skips non-comment change fields" do
      summary = run(comment_payload(field: "mentions"))
      expect(summary).to include(comments: 0, skipped: 1)
    end
  end

  describe "postbacks" do
    it "fires on_postback for icebreaker/button taps" do
      payload = { "entry" => [ { "id" => "IGACC", "messaging" => [
        { "sender" => { "id" => "CUST" }, "postback" => { "payload" => "GO", "title" => "Start" } }
      ] } ] }
      summary = run(payload)
      expect(summary[:postbacks]).to eq(1)
      expect(seen_postbacks.first).to include(payload: "GO", title: "Start")
    end

    it "skips a messaging event that is neither a message nor a postback" do
      payload = { "entry" => [ { "id" => "IGACC", "messaging" => [ { "sender" => { "id" => "CUST" }, "read" => {} } ] } ] }
      expect(run(payload)).to include(skipped: 1)
    end
  end

  describe "account resolution" do
    it "matches an account by page_id" do
      InstagramConnect::Account.create!(ig_user_id: "OTHER", page_id: "PAGE1", auth_path: "facebook_login", access_token: "t")
      summary = run(dm_payload(mid: "p1", sender: "CUST", recipient: "PAGE1", entry_id: "PAGE1"))
      expect(summary[:messages]).to eq(1)
    end

    it "skips an entry for an unknown account" do
      summary = run(dm_payload(mid: "x", sender: "CUST", recipient: "NOPE", entry_id: "NOPE"))
      expect(summary).to include(messages: 0, skipped: 1)
      expect(InstagramConnect::Message.count).to eq(0)
    end
  end

  describe "with no handlers configured" do
    let(:config) { InstagramConnect::Configuration.new.tap { |c| c.auth_path = :instagram_login } }

    it "still persists without invoking any handler" do
      expect { run(dm_payload(mid: "m1", sender: "CUST", recipient: "IGACC")) }.not_to raise_error
      expect { run(comment_payload) }.not_to raise_error
      expect(InstagramConnect::Message.count).to eq(1)
    end
  end

  it "tolerates an empty payload" do
    expect(run({})).to eq(messages: 0, comments: 0, postbacks: 0, skipped: 0)
  end
end

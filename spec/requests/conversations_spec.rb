require "rails_helper"

RSpec.describe "Conversations inbox", type: :request do
  let(:account) { InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "TOK") }

  def thread(igsid:, **attrs)
    convo = InstagramConnect::Conversation.locate(account: account, igsid: igsid)
    convo.update!(attrs) if attrs.any?
    convo
  end

  describe "GET /instagram/conversations" do
    it "lists threads" do
      thread(igsid: "A", last_message_preview: "hey there", last_message_at: 1.hour.ago)
      get "/instagram/conversations"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("hey there")
    end

    it "renders an empty state and honors the page param" do
      get "/instagram/conversations", params: { page: 2 }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No conversations yet")
    end
  end

  describe "GET /instagram/conversations/:id" do
    it "shows the thread and clears the unread count" do
      convo = thread(igsid: "A", unread_count: 3, last_inbound_at: 1.hour.ago)
      convo.messages.create!(direction: "inbound", status: "received", kind: "dm", body: "hello world")

      get "/instagram/conversations/#{convo.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("hello world")
      expect(convo.reload.unread_count).to eq(0)
    end

    it "shows the closed-window notice when no reply is allowed" do
      convo = thread(igsid: "A", unread_count: 0, last_inbound_at: 8.days.ago)
      get "/instagram/conversations/#{convo.id}"
      expect(response.body).to include("reply window has closed")
    end
  end

  describe "POST /instagram/conversations/:id/messages" do
    it "queues an outbound reply" do
      convo = thread(igsid: "A", last_inbound_at: 1.hour.ago)

      expect do
        post "/instagram/conversations/#{convo.id}/messages", params: { body: "on my way" }
      end.to change { convo.messages.outbound.count }.by(1)

      expect(response).to redirect_to("/instagram/conversations/#{convo.id}")
      expect(InstagramConnect::SendMessageJob).to have_been_enqueued
    end

    it "rejects a blank reply" do
      convo = thread(igsid: "A", last_inbound_at: 1.hour.ago)

      expect do
        post "/instagram/conversations/#{convo.id}/messages", params: { body: "   " }
      end.not_to change(InstagramConnect::Message, :count)

      expect(response).to redirect_to("/instagram/conversations/#{convo.id}")
    end
  end
end

require "rails_helper"

RSpec.describe InstagramConnect::SendMessageJob do
  let(:account) { InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "TOK") }
  let(:conversation) { InstagramConnect::Conversation.locate(account: account, igsid: "CUST") }

  def pending_message(**attrs)
    InstagramConnect::Message.create!(
      { conversation: conversation, direction: "outbound", status: "pending", kind: "dm", source: "manual", body: "hello" }.merge(attrs)
    )
  end

  def stub_send(status: 200, body: { message_id: "mid_1" })
    stub_request(:post, "https://graph.instagram.com/v21.0/me/messages")
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "sends within the standard window and marks the message sent" do
    conversation.update!(last_inbound_at: 1.hour.ago)
    message = pending_message
    req = stub_send

    described_class.perform_now(message.id)

    expect(message.reload.status).to eq("sent")
    expect(message.ig_message_id).to eq("mid_1")
    expect(req).to have_been_requested
  end

  it "applies the HUMAN_AGENT tag in the extended window" do
    conversation.update!(last_inbound_at: 3.days.ago)
    message = pending_message
    req = stub_request(:post, "https://graph.instagram.com/v21.0/me/messages")
      .with(body: hash_including("tag" => "HUMAN_AGENT"))
      .to_return(status: 200, body: { message_id: "mid_2" }.to_json, headers: { "Content-Type" => "application/json" })

    described_class.perform_now(message.id)

    expect(message.reload.status).to eq("sent")
    expect(message.message_tag).to eq("HUMAN_AGENT")
    expect(req).to have_been_requested
  end

  it "fails the message when the window is closed" do
    conversation.update!(last_inbound_at: 8.days.ago)
    message = pending_message

    described_class.perform_now(message.id)

    expect(message.reload.status).to eq("failed")
    expect(message.failure_reason).to eq("outside_messaging_window")
  end

  it "fails the message when there was never an inbound message" do
    message = pending_message
    described_class.perform_now(message.id)
    expect(message.reload.status).to eq("failed")
  end

  it "does nothing for a message that is not pending" do
    conversation.update!(last_inbound_at: 1.hour.ago)
    message = pending_message(status: "sent")

    described_class.perform_now(message.id)

    expect(message.reload.status).to eq("sent")
    expect(a_request(:post, %r{graph\.instagram\.com})).not_to have_been_made
  end

  it "marks the message failed when the API returns an error" do
    conversation.update!(last_inbound_at: 1.hour.ago)
    message = pending_message
    stub_send(status: 400, body: { error: { message: "bad recipient", code: 10 } })

    described_class.perform_now(message.id)

    expect(message.reload.status).to eq("failed")
    expect(message.error_message).to eq("bad recipient")
    expect(message.failure_reason).to eq("10")
  end

  it "handles an API error that carries no error code" do
    conversation.update!(last_inbound_at: 1.hour.ago)
    message = pending_message
    stub_send(status: 500, body: {})

    described_class.perform_now(message.id)

    expect(message.reload.status).to eq("failed")
    expect(message.failure_reason).to be_nil
  end
end

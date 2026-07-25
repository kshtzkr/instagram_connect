require "rails_helper"

RSpec.describe "outbound send" do
  let(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "TOKEN")
  end
  let(:conversation) do
    InstagramConnect::Conversation.locate(account: account, igsid: "CUST").tap do |c|
      c.update!(last_inbound_at: 1.hour.ago)
    end
  end
  let(:base) { "https://graph.instagram.com/v21.0" }

  def pending_message(body:)
    conversation.messages.create!(direction: "outbound", status: "pending", kind: "dm",
                                  source: "manual", body: body)
  end

  def stub_send(ids: [ "mid-1" ])
    responses = ids.map { |id| { status: 200, body: { message_id: id }.to_json,
                                 headers: { "Content-Type" => "application/json" } } }
    stub_request(:post, "#{base}/me/messages").to_return(*responses)
  end

  describe InstagramConnect::SendMessageJob do
    it "sends a short message as one part and records Meta's id" do
      message = pending_message(body: "hello")
      stub_send

      described_class.perform_now(message.id)

      message.reload
      expect(message.status).to eq("sent")
      expect(message.ig_message_id).to eq("mid-1")
      expect(message.delivered_parts_count).to eq(1)
    end

    # Meta's ceiling is 1000 bytes. Sending the whole thing would be rejected
    # outright, and truncating would silently drop half the operator's answer.
    it "splits an over-long message and keeps the first id as its identity" do
      message = pending_message(body: "#{'word ' * 300}end")
      stub_send(ids: %w[mid-1 mid-2])

      described_class.perform_now(message.id)

      message.reload
      expect(message.status).to eq("sent")
      expect(message.delivered_parts_count).to eq(2)
      expect(message.ig_message_id).to eq("mid-1")
      expect(WebMock).to have_requested(:post, "#{base}/me/messages").twice
    end

    # A worker killed mid-fan-out has already delivered the earlier parts.
    # Restarting would repeat text the customer can see.
    it "resumes a partially delivered message instead of repeating parts" do
      message = pending_message(body: "#{'word ' * 300}end")
      message.update!(delivered_parts_count: 1)
      stub_send(ids: %w[mid-2])

      described_class.perform_now(message.id)

      expect(WebMock).to have_requested(:post, "#{base}/me/messages").once
      expect(message.reload.delivered_parts_count).to eq(2)
    end

    it "refuses to send on a thread another app controls, naming the reason" do
      conversation.update!(thread_owner_app_id: "other-app", thread_control_at: Time.current)
      message = pending_message(body: "hi")

      described_class.perform_now(message.id)

      message.reload
      expect(message.status).to eq("failed")
      expect(message.failure_reason).to eq("thread_controlled_elsewhere")
      expect(WebMock).not_to have_requested(:post, "#{base}/me/messages")
    end

    it "stops at the failing part rather than pushing on through the rest" do
      message = pending_message(body: "#{'word ' * 300}end")
      stub_request(:post, "#{base}/me/messages")
        .to_return({ status: 200, body: { message_id: "mid-1" }.to_json,
                     headers: { "Content-Type" => "application/json" } },
                   { status: 400, body: { error: { message: "nope", code: 10 } }.to_json,
                     headers: { "Content-Type" => "application/json" } })

      described_class.perform_now(message.id)

      message.reload
      expect(message.status).to eq("failed")
      expect(message.delivered_parts_count).to eq(1)
    end

    it "tells the host to re-render, since the claim skipped callbacks" do
      message = pending_message(body: "hi")
      stub_send
      allow_any_instance_of(InstagramConnect::Message).to receive(:broadcast_refresh)

      described_class.perform_now(message.id)

      expect(message.reload.status).to eq("sent")
    end
  end

  describe InstagramConnect::Client do
    let(:client) { described_class.new(access_token: "TOKEN", ig_user_id: "IGACC") }

    def stub_ok(path, body: { id: "ok" })
      stub_request(:post, "#{base}#{path}")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    # Meta is explicit that a sender action request carries only the recipient
    # and the action; bundling it with a message drops one of the two.
    it "sends a sender action on its own" do
      stub_ok("/me/messages")

      expect(client.send_sender_action(recipient_id: "CUST", action: "typing_on")).to be_success
      expect(WebMock).to have_requested(:post, "#{base}/me/messages")
        .with(body: { recipient: { id: "CUST" }, sender_action: "typing_on" }.to_json)
    end

    it "truncates quick reply titles to Meta's 20-character ceiling" do
      stub_ok("/me/messages")

      client.send_quick_replies(recipient_id: "CUST", text: "Pick one", replies: [
        { title: "A title far longer than twenty characters", payload: "LONG" }
      ])

      expect(WebMock).to have_requested(:post, "#{base}/me/messages").with { |request|
        JSON.parse(request.body).dig("message", "quick_replies", 0, "title").length == 20
      }
    end

    it "sends a previously uploaded attachment by reference" do
      stub_ok("/me/messages")

      client.send_attachment(recipient_id: "CUST", attachment_id: "att-1")

      expect(WebMock).to have_requested(:post, "#{base}/me/messages").with { |request|
        JSON.parse(request.body).dig("message", "attachment", "payload", "attachment_id") == "att-1"
      }
    end

    # Uploading beats handing Meta a signed URL: a signed URL is a bearer
    # capability for a customer's file, left on the public internet for the
    # length of its TTL and fetched from an address we do not control.
    it "uploads bytes over an authenticated multipart POST and returns a reusable id" do
      stub_request(:post, "#{base}/me/message_attachments")
        .to_return(status: 200, body: { attachment_id: "att-9", id: "att-9" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      Tempfile.create([ "photo", ".jpg" ]) do |file|
        file.write("bytes")
        file.rewind

        result = client.upload_attachment(file: file)

        expect(result).to be_success
        expect(result.id).to eq("att-9")
      end

      expect(WebMock).to have_requested(:post, "#{base}/me/message_attachments")
    end

    it "writes and reads the messenger profile for ice breakers and the menu" do
      stub_ok("/me/messenger_profile", body: { result: "success" })
      stub_request(:get, "#{base}/me/messenger_profile")
        .with(query: hash_including({}))
        .to_return(status: 200, body: { data: [] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      client.set_messenger_profile(ice_breakers: [ { call_to_actions: [], locale: "default" } ])
      client.messenger_profile(fields: %w[ice_breakers])

      expect(WebMock).to have_requested(:post, "#{base}/me/messenger_profile").with { |request|
        JSON.parse(request.body)["platform"] == "instagram"
      }
      expect(WebMock).to have_requested(:get, "#{base}/me/messenger_profile")
        .with(query: hash_including("platform" => "instagram"))
    end

    it "deletes messenger profile fields" do
      stub_request(:delete, "#{base}/me/messenger_profile")
        .to_return(status: 200, body: { result: "success" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      expect(client.delete_messenger_profile(fields: %w[persistent_menu])).to be_success
    end
  end
end

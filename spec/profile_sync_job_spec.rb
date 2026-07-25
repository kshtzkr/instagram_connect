require "rails_helper"

RSpec.describe InstagramConnect::ProfileSyncJob do
  let(:base) { "https://graph.instagram.com/v21.0" }
  let!(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "t")
  end
  let(:conversation) { InstagramConnect::Conversation.locate(account: account, igsid: "CUST") }

  def stub_json(url, body, status: 200)
    stub_request(:get, url).with(query: hash_including({}))
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "the connected account" do
    it "fills in the handle and stats the columns have always had room for" do
      stub_json("#{base}/IGACC", { username: "escapes.asia", name: "Escapes Asia",
                                   profile_picture_url: "https://cdn/a.jpg",
                                   followers_count: 4800, media_count: 210 })

      described_class.perform_now(account_id: account.id)

      account.reload
      expect(account.username).to eq("escapes.asia")
      expect(account.name).to eq("Escapes Asia")
      expect(account.followers_count).to eq(4800)
      expect(account.profile_synced_at).to be_present
    end

    # A display name changes rarely, and every refetch spends budget that
    # inbound message handling needs more.
    it "does not refetch a profile synced recently" do
      account.update!(profile_synced_at: 1.day.ago)

      described_class.perform_now(account_id: account.id)

      expect(WebMock).not_to have_requested(:get, "#{base}/IGACC")
    end

    it "refetches once the profile has gone stale" do
      account.update!(profile_synced_at: 8.days.ago)
      stub_json("#{base}/IGACC", { username: "escapes.asia" })

      described_class.perform_now(account_id: account.id)

      expect(account.reload.username).to eq("escapes.asia")
    end

    it "keeps what it already knew when Meta omits a field" do
      account.update!(username: "existing", name: "Existing Name")
      stub_json("#{base}/IGACC", { followers_count: 10 })

      described_class.perform_now(account_id: account.id)

      account.reload
      expect(account.username).to eq("existing")
      expect(account.name).to eq("Existing Name")
    end

    it "logs and moves on when the lookup fails" do
      stub_json("#{base}/IGACC", { error: { message: "nope", code: 10 } }, status: 400)

      expect { described_class.perform_now(account_id: account.id) }.not_to raise_error
      expect(account.reload.username).to be_nil
    end

    it "still moves on when the host configured no logger" do
      InstagramConnect.configuration.logger = nil
      stub_json("#{base}/IGACC", { error: { message: "nope" } }, status: 400)

      expect { described_class.perform_now(account_id: account.id) }.not_to raise_error
    end

    it "syncs every active account when given nothing specific" do
      stub_json("#{base}/IGACC", { username: "escapes.asia" })

      described_class.perform_now

      expect(account.reload.username).to eq("escapes.asia")
    end

    it "does nothing for an account that has been deleted" do
      expect { described_class.perform_now(account_id: -1) }.not_to raise_error
    end
  end

  describe "a conversation" do
    # Without this an inbox shows a 17-digit Instagram-scoped id where a
    # person's handle belongs.
    it "gives the thread a name and a face" do
      stub_json("#{base}/CUST", { username: "traveller", name: "Sam Traveller",
                                  profile_pic: "https://cdn/p.jpg" })

      described_class.perform_now(conversation_id: conversation.id)

      conversation.reload
      expect(conversation.username).to eq("traveller")
      expect(conversation.display_name).to eq("Sam Traveller")
      expect(conversation.profile_picture_url).to eq("https://cdn/p.jpg")
    end

    # Someone who blocked the business, or deleted their account, cannot be
    # looked up. Stamping the attempt stops the job retrying them on every
    # message they ever sent.
    it "stamps the attempt even when the customer cannot be looked up" do
      stub_json("#{base}/CUST", { error: { message: "unavailable", code: 100 } }, status: 400)

      described_class.perform_now(conversation_id: conversation.id)

      expect(conversation.reload.profile_synced_at).to be_present
      expect(conversation.username).to be_nil
    end

    it "does not refetch a thread synced recently" do
      conversation.update!(profile_synced_at: 1.hour.ago)

      described_class.perform_now(conversation_id: conversation.id)

      expect(WebMock).not_to have_requested(:get, "#{base}/CUST")
    end

    it "does nothing for a conversation that has been deleted" do
      expect { described_class.perform_now(conversation_id: -1) }.not_to raise_error
    end
  end

  describe "ingest" do
    # Fetched once, when the thread first appears — not on every message.
    it "enqueues a sync the first time a thread is seen, and not again" do
      payload = lambda do |mid|
        { "object" => "instagram",
          "entry" => [ { "id" => "IGACC", "messaging" => [
            { "sender" => { "id" => "CUST" }, "recipient" => { "id" => "IGACC" },
              "message" => { "mid" => mid, "text" => "hi" } }
          ] } ] }
      end

      InstagramConnect::Ingest.call(payload: payload.call("m1"))
      InstagramConnect::Conversation.last.update!(profile_synced_at: Time.current)
      InstagramConnect::Ingest.call(payload: payload.call("m2"))

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs
        .count { |job| job[:job] == described_class }
      expect(enqueued).to eq(1)
    end
  end
end

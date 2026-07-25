require "rails_helper"

RSpec.describe InstagramConnect::AccountReadinessJob do
  let(:base) { "https://graph.instagram.com/v21.0" }

  let!(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGACC", page_id: "PAGE1",
                                      auth_path: "instagram_login", access_token: "USER-TOKEN")
  end

  def stub_me(id:)
    stub_request(:get, "#{base}/me").with(query: hash_including({}))
      .to_return(status: 200, body: { id: id }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  def stub_pages(pages)
    stub_request(:get, "#{base}/me/accounts").with(query: hash_including({}))
      .to_return(status: 200, body: { data: pages }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  def stub_subscriptions(fields)
    stub_request(:get, "#{base}/PAGE1/subscribed_apps").with(query: hash_including({}))
      .to_return(status: 200, body: { data: [ { subscribed_fields: fields } ] }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  def stub_subscribe
    stub_request(:post, "#{base}/PAGE1/subscribed_apps")
      .to_return(status: 200, body: { success: true }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  describe ".enqueue_if_needed" do
    it "does nothing when the app is not configured" do
      InstagramConnect.configuration.app_id = nil

      expect(described_class.enqueue_if_needed).to eq(:nothing_to_do)
    end

    it "does nothing when no account has a Page" do
      account.update!(page_id: nil)

      expect(described_class.enqueue_if_needed).to eq(:nothing_to_do)
    end

    it "enqueues when a connectable account exists" do
      expect(described_class.enqueue_if_needed).to eq(:enqueued)
    end
  end

  describe "token grade" do
    # The messaging endpoints and the subscription below are Page-token
    # operations; the OAuth exchange only ever hands back a user token.
    it "swaps the user token for the Page token and clears the expiry" do
      account.update!(token_expires_at: 30.days.from_now)
      stub_me(id: "PERSON")
      stub_pages([ { "id" => "OTHER", "access_token" => "nope" },
                   { "id" => "PAGE1", "access_token" => "PAGE-TOKEN" } ])
      stub_subscriptions(described_class.subscribed_fields)

      described_class.perform_now

      account.reload
      expect(account.page_access_token).to eq("PAGE-TOKEN")
      expect(account.api_token).to eq("PAGE-TOKEN")
      expect(account.token_expires_at).to be_nil
      expect(account.page_token_verified_at).to be_present
    end

    # A host that swapped the token itself before this job existed arrives here
    # holding a Page token in access_token. /me/accounts cannot be called with
    # one, so the Page token cannot be re-derived — adopt what is there rather
    # than attempt a recovery that cannot work.
    it "adopts a token that is already a Page token" do
      stub_me(id: "PAGE1")
      stub_subscriptions(described_class.subscribed_fields)

      described_class.perform_now

      expect(account.reload.page_access_token).to eq("USER-TOKEN")
      expect(WebMock).not_to have_requested(:get, "#{base}/me/accounts")
    end

    it "flags an account whose operator no longer administers the Page" do
      stub_me(id: "PERSON")
      stub_pages([ { "id" => "OTHER", "access_token" => "x" } ])

      described_class.perform_now

      account.reload
      expect(account.needs_reconnect).to be(true)
      expect(account.readiness_error).to include("no Page token")
    end

    it "does not re-probe an account already verified" do
      account.update!(page_access_token: "PAGE-TOKEN", page_token_verified_at: 1.hour.ago)
      stub_subscriptions(described_class.subscribed_fields)

      described_class.perform_now

      expect(WebMock).not_to have_requested(:get, "#{base}/me")
    end
  end

  describe "page subscription" do
    before do
      account.update!(page_access_token: "PAGE-TOKEN", page_token_verified_at: 1.hour.ago)
    end

    # Ticking the fields in the app dashboard subscribes the app. Meta delivers
    # nothing until the Page lists the app in its subscribed_apps.
    it "subscribes the Page when fields are missing, and records what is live" do
      stub_subscriptions(%w[messages])
      stub_subscribe

      described_class.perform_now

      expect(WebMock).to have_requested(:post, "#{base}/PAGE1/subscribed_apps")
      expect(account.reload.subscribed_field_list).to eq(described_class.subscribed_fields)
      expect(account.subscriptions_synced_at).to be_present
    end

    it "does not re-subscribe a Page that already carries every field" do
      stub_subscriptions(described_class.subscribed_fields)

      described_class.perform_now

      expect(WebMock).not_to have_requested(:post, "#{base}/PAGE1/subscribed_apps")
    end

    # The list has to track what Ingest can parse. Maintained separately they
    # drift, and the host silently receives events it drops.
    it "subscribes exactly the fields the ingest registry knows about" do
      expect(described_class.subscribed_fields)
        .to eq(InstagramConnect::Ingest::Registry.subscribable_fields)
    end
  end

  it "records the failure on the account and carries on with the rest" do
    other = InstagramConnect::Account.create!(ig_user_id: "IG2", page_id: "PAGE2",
                                              auth_path: "instagram_login", access_token: "t2")
    stub_request(:get, "#{base}/me").with(query: hash_including({}))
      .to_return(status: 400, body: { error: { message: "boom" } }.to_json,
                 headers: { "Content-Type" => "application/json" })

    described_class.perform_now

    expect(account.reload.readiness_error).to include("boom")
    expect(other.reload.readiness_error).to include("boom")
  end

  it "still records the failure when the host configured no logger" do
    InstagramConnect.configuration.logger = nil
    stub_request(:get, "#{base}/me").with(query: hash_including({}))
      .to_return(status: 500, body: "server error", headers: { "Content-Type" => "text/plain" })

    expect { described_class.perform_now }.not_to raise_error
    expect(account.reload.readiness_error).to include("HTTP 500")
  end

  it "clears a stale error once the account comes back healthy" do
    account.update!(page_access_token: "PAGE-TOKEN", page_token_verified_at: 1.hour.ago,
                    readiness_error: "earlier failure")
    stub_subscriptions(described_class.subscribed_fields)

    described_class.perform_now

    expect(account.reload.readiness_error).to be_nil
  end

  it "does nothing at all when the app is not configured" do
    InstagramConnect.configuration.app_id = nil

    described_class.perform_now

    expect(WebMock).not_to have_requested(:get, "#{base}/me")
  end
end

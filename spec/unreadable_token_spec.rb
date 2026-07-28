require "rails_helper"

# The 2026-07-27 production failure: encryption keys were rotated, the stored
# access token no longer decrypted, and support_unencrypted_data handed the
# ENVELOPE back instead of raising. Every Graph call then sent that JSON blob
# as the bearer token and Meta answered "Invalid OAuth access token - Cannot
# parse access token" — with nothing anywhere saying the cause was local.
RSpec.describe "an access token this process cannot decrypt" do
  let(:base) { "https://graph.facebook.com/v21.0" }
  let(:envelope) { '{"p":"cSnZefV5UY6mKEfy","h":{"iv":"kn/M9USq7StGjNqN","at":"N4Mgt"}}' }

  let!(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGUSER", auth_path: "facebook_login",
                                      access_token: "good-token", page_id: "PAGE1", active: true)
  end

  def store_envelope!
    # Bypass the attribute layer to plant exactly what a failed decrypt leaves
    # in memory: the envelope, as a value.
    account.update_columns(access_token: envelope, page_access_token: nil)
    account.reload
  end

  it "is recognised rather than sent to Meta" do
    expect(account.token_readable?).to be(true)

    store_envelope!

    expect(account.token_readable?).to be(false)
    expect { account.client }.to raise_error(InstagramConnect::TokenUnreadableError, /reconnect/i)
    expect(WebMock).not_to have_requested(:any, /graph\.facebook\.com/)
  end

  it "records why on the account, for the host's health screen" do
    store_envelope!

    expect { account.client }.to raise_error(InstagramConnect::TokenUnreadableError)

    expect(account.reload.readiness_error).to match(/cannot be decrypted/i)
    expect(account.readiness_error).to match(/reconnect/i)
  end

  it "aborts a sync job with the actionable message instead of Meta's opaque one" do
    store_envelope!

    expect(Rails.logger).to receive(:error).with(/aborted:.*reconnect/i)
    InstagramConnect::SyncCommentsJob.perform_now(account.id, "MEDIA1")

    expect(WebMock).not_to have_requested(:any, /graph\.facebook\.com/)
  end

  # Production 2026-07-28: with previous-keys wired, reading a token no key
  # set opens RAISES (AEAD tag verification) instead of returning ciphertext —
  # and the raise came from inside this very guard, 500ing the comments
  # screen into Turbo's "Content missing".
  it "stays false when the read itself raises" do
    store_envelope!
    allow(account).to receive(:api_token)
      .and_raise(ActiveRecord::Encryption::Errors::Decryption)

    expect(account.token_readable?).to be(false)
  end

  it "treats a blank token as unusable too" do
    account.update_columns(access_token: nil, page_access_token: nil)

    expect(account.reload.token_readable?).to be(false)
  end

  it "clears the way again once a fresh token is stored" do
    store_envelope!
    expect { account.client }.to raise_error(InstagramConnect::TokenUnreadableError)

    account.update!(access_token: "fresh-token", readiness_error: nil)

    expect(account.token_readable?).to be(true)
    expect(account.client).to be_a(InstagramConnect::Client)
  end
  # AccountReadinessJob builds its own Authorization header instead of going
  # through Account#client, so the guard there never covered it: production
  # kept shipping the envelope to Meta and recording the answer as if the
  # SUBSCRIPTION were broken.
  describe "the readiness pass, which builds its own header" do
    it "skips the account and says the token is the problem" do
      store_envelope!
      InstagramConnect.configuration.app_id = "APP"

      InstagramConnect::AccountReadinessJob.perform_now

      expect(account.reload.readiness_error).to match(/cannot be decrypted/i)
      expect(WebMock).not_to have_requested(:any, /graph\.facebook\.com/)
    end

    it "refuses to build an Authorization header around an unreadable token" do
      store_envelope!
      job = InstagramConnect::AccountReadinessJob.new

      expect { job.send(:bearer, account) }
        .to raise_error(InstagramConnect::TokenUnreadableError, /reconnect/i)
    end
  end

  # The send job claims the message into "sending" BEFORE building a client,
  # so the generic swallow left the bubble spinning forever with no failed
  # state, no retry button, and no reason on screen — production, 2026-07-28.
  describe "a send against an unreadable token" do
    it "fails the message visibly instead of stranding it in sending" do
      conversation = InstagramConnect::Conversation.create!(
        account: account, igsid: "CUST1", last_inbound_at: 5.minutes.ago
      )
      message = InstagramConnect::Message.create!(
        conversation: conversation, direction: "outbound", status: "pending",
        kind: "dm", source: "manual", body: "hi"
      )
      store_envelope!

      InstagramConnect::SendMessageJob.perform_now(message.id)

      message.reload
      expect(message.status).to eq("failed")
      expect(message.failure_reason).to eq("token_unreadable")
      expect(message.error_message).to match(/reconnect/i)
      expect(WebMock).not_to have_requested(:any, /graph\.facebook\.com/)
    end
  end

end

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
end

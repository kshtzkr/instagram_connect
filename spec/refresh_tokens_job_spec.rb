require "rails_helper"

RSpec.describe InstagramConnect::RefreshTokensJob do
  def account(**attrs)
    InstagramConnect::Account.create!({ auth_path: "instagram_login", access_token: "tok" }.merge(attrs))
  end

  it "refreshes only active accounts whose token expires within the window" do
    due = account(ig_user_id: "DUE", token_expires_at: 1.day.from_now)
    account(ig_user_id: "FAR", token_expires_at: 30.days.from_now)
    account(ig_user_id: "NONE", token_expires_at: nil)
    account(ig_user_id: "OFF", token_expires_at: 1.day.from_now, active: false)

    refreshed = []
    allow_any_instance_of(InstagramConnect::Account).to receive(:refresh_access_token!) do |acc|
      refreshed << acc.ig_user_id
    end

    described_class.new.perform

    expect(refreshed).to eq([ due.ig_user_id ])
  end

  it "logs and continues when one account fails to refresh" do
    account(ig_user_id: "A", token_expires_at: 1.day.from_now)
    account(ig_user_id: "B", token_expires_at: 2.days.from_now)

    allow_any_instance_of(InstagramConnect::Account).to receive(:refresh_access_token!).and_raise("token dead")
    logger = instance_double(Logger, error: nil)
    InstagramConnect.configuration.logger = logger

    expect { described_class.new.perform }.not_to raise_error
    expect(logger).to have_received(:error).twice
  end

  it "does not blow up when a refresh fails and no logger is configured" do
    account(ig_user_id: "A", token_expires_at: 1.day.from_now)
    allow_any_instance_of(InstagramConnect::Account).to receive(:refresh_access_token!).and_raise("dead")
    InstagramConnect.configuration.logger = nil

    expect { described_class.new.perform }.not_to raise_error
  end
end

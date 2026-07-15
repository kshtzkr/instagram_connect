require "rails_helper"

RSpec.describe InstagramConnect::Account do
  def build_account(**attrs)
    described_class.new({ ig_user_id: "IG1", auth_path: "facebook_login", access_token: "tok" }.merge(attrs))
  end

  describe "validations" do
    it "requires ig_user_id and auth_path" do
      account = described_class.new
      expect(account).not_to be_valid
      expect(account.errors[:ig_user_id]).to be_present
      expect(account.errors[:auth_path]).to be_present
    end

    it "enforces ig_user_id uniqueness" do
      build_account.save!
      expect(build_account).not_to be_valid
    end
  end

  describe "scopes" do
    it ".active returns only active accounts" do
      active = build_account(ig_user_id: "A", active: true).tap(&:save!)
      build_account(ig_user_id: "B", active: false).save!
      expect(described_class.active).to contain_exactly(active)
    end

    it ".token_expiring_before returns accounts with a token expiring by the cutoff" do
      soon = build_account(ig_user_id: "A", token_expires_at: 1.day.from_now).tap(&:save!)
      build_account(ig_user_id: "B", token_expires_at: 30.days.from_now).save!
      build_account(ig_user_id: "C", token_expires_at: nil).save!

      expect(described_class.token_expiring_before(7.days.from_now)).to contain_exactly(soon)
    end
  end

  describe "#token_expired?" do
    it "is false when there is no expiry" do
      expect(build_account(token_expires_at: nil).token_expired?).to be(false)
    end

    it "is false for a future expiry and true for a past one" do
      expect(build_account(token_expires_at: 1.hour.from_now).token_expired?).to be(false)
      expect(build_account(token_expires_at: 1.hour.ago).token_expired?).to be(true)
    end
  end

  describe "#refresh_access_token!" do
    it "persists the token returned by the auth strategy" do
      InstagramConnect.configure do |c|
        c.auth_path = :facebook_login
        c.app_id = "APPID"
        c.app_secret = "SECRET"
      end
      account = build_account(token_expires_at: 1.day.from_now).tap(&:save!)

      # Facebook-Login refresh is a no-op that returns the token unchanged with
      # a nil expiry — a real, HTTP-free code path.
      account.refresh_access_token!

      expect(account.reload.token_expires_at).to be_nil
      expect(account.access_token).to eq("tok")
    end
  end

  describe "token encryption" do
    it "stores the access token encrypted at rest" do
      account = build_account(access_token: "SUPER-SECRET").tap(&:save!)
      raw = described_class.connection.select_value(
        "SELECT access_token FROM instagram_connect_accounts WHERE id = #{account.id}"
      )
      expect(raw).not_to include("SUPER-SECRET")
      expect(account.reload.access_token).to eq("SUPER-SECRET")
    end
  end
end

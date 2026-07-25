require "instagram_connect"
require "instagram_connect/cli"

RSpec.describe InstagramConnect::CLI do
  it "prints the configuration checks for `doctor`" do
    InstagramConnect.configure do |c|
      c.auth_path = :instagram_login
      c.app_id = "id"
      c.app_secret = "s"
      c.verify_token = "v"
    end

    expect { described_class.start([ "doctor" ]) }.to output(/auth_path is valid/).to_stdout
  end

  it "marks a failing check MISSING so the operator sees what to fix" do
    allow(InstagramConnect::Doctor).to receive(:run)
      .and_return([ { label: "app_secret is set", ok: false } ])

    expect { described_class.start([ "doctor" ]) }.to output(/MISSING\s+app_secret is set/).to_stdout
  end

  it "exits on failure" do
    expect(described_class.exit_on_failure?).to be(true)
  end
end

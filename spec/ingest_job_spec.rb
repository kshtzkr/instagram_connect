require "rails_helper"

RSpec.describe InstagramConnect::IngestJob do
  it "delegates the payload to Ingest" do
    InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "t")
    payload = { "entry" => [ {
      "id" => "IGACC",
      "messaging" => [ { "sender" => { "id" => "C" }, "recipient" => { "id" => "IGACC" }, "message" => { "mid" => "m1", "text" => "hi" } } ]
    } ] }

    expect { described_class.perform_now(payload) }.to change(InstagramConnect::Message, :count).by(1)
  end
end

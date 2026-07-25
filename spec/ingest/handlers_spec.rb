require "rails_helper"

RSpec.describe InstagramConnect::Ingest::Handlers do
  let(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "t")
  end
  let(:envelope) do
    InstagramConnect::Ingest::Envelope.new(
      account: account, field: "unknown", event: {}, config: InstagramConnect.configuration
    )
  end

  describe InstagramConnect::Ingest::Handlers::Base do
    it "refuses to run undefined — a registered handler must implement #call" do
      expect { described_class.new(envelope).call }.to raise_error(NotImplementedError)
    end

    it "declares no dedupe key by default, so the dispatcher hashes the payload" do
      expect(described_class.dedupe_key({})).to be_nil
    end
  end

  describe InstagramConnect::Ingest::Handlers::Unknown do
    # Unknown never persists anything: the dispatcher banks the row and marks it
    # unhandled. It exists so the registry always resolves to a class, and so
    # the ledger records which handler was chosen.
    it "persists nothing and requests no callback" do
      handler = described_class.new(envelope)

      expect(handler.call).to be_nil
      expect(handler.notification).to be_nil
    end
  end

  describe "dedupe keys" do
    it "reads a message's mid" do
      event = { "message" => { "mid" => "m1" } }

      expect(InstagramConnect::Ingest::Handlers::Messages.dedupe_key(event)).to eq("m1")
    end

    it "reads a postback's mid" do
      event = { "postback" => { "mid" => "p1", "payload" => "GO" } }

      expect(InstagramConnect::Ingest::Handlers::MessagingPostbacks.dedupe_key(event)).to eq("p1")
    end

    it "reads a comment's id" do
      event = { "value" => { "id" => "c1" } }

      expect(InstagramConnect::Ingest::Handlers::Comments.dedupe_key(event)).to eq("c1")
    end

    it "requires an id for the handlers that cannot dedupe without one" do
      expect(InstagramConnect::Ingest::Handlers::Messages.requires_dedupe_key?).to be(true)
      expect(InstagramConnect::Ingest::Handlers::Comments.requires_dedupe_key?).to be(true)
    end
  end
end

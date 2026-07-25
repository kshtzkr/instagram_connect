require "rails_helper"

RSpec.describe InstagramConnect::Ingest::Registry do
  describe ".messaging_field_for" do
    # Meta delivers every messaging event under entry.messaging whatever
    # subscription produced it, so the field has to be recovered from the shape.
    {
      "messages" => { "message" => { "mid" => "m1", "text" => "hi" } },
      "message_reactions" => { "reaction" => { "mid" => "m1", "action" => "react" } },
      "messaging_postbacks" => { "postback" => { "payload" => "GO" } },
      "messaging_seen" => { "read" => { "mid" => "m1" } },
      "messaging_referral" => { "referral" => { "ref" => "campaign" } },
      "messaging_optins" => { "optin" => { "type" => "notification_messages" } },
      "messaging_handover" => { "pass_thread_control" => { "new_owner_app_id" => "1" } }
    }.each do |field, event|
      it "infers #{field}" do
        expect(described_class.messaging_field_for(event)).to eq(field)
      end
    end

    it "infers message_echoes before messages, since an echo carries a message too" do
      event = { "message" => { "mid" => "m1", "is_echo" => true } }

      expect(described_class.messaging_field_for(event)).to eq("message_echoes")
    end

    it "recognises take_thread_control and request_thread_control as handover" do
      expect(described_class.messaging_field_for("take_thread_control" => {})).to eq("messaging_handover")
      expect(described_class.messaging_field_for("request_thread_control" => {})).to eq("messaging_handover")
    end

    # A referral nested inside a message or postback belongs to that event, so
    # the ordered shape tests must not promote it to a referral of its own.
    it "keeps a nested referral with its parent message" do
      event = { "message" => { "mid" => "m1" }, "referral" => { "ref" => "x" } }

      expect(described_class.messaging_field_for(event)).to eq("messages")
    end

    it "falls back to unknown for a shape it does not recognise" do
      expect(described_class.messaging_field_for("something_new" => {})).to eq("unknown")
    end
  end

  describe ".handler_for" do
    it "maps a known field to its handler" do
      expect(described_class.handler_for("messages")).to eq(InstagramConnect::Ingest::Handlers::Messages)
      expect(described_class.handler_for("live_comments")).to eq(InstagramConnect::Ingest::Handlers::Comments)
    end

    it "falls back to Unknown so the registry always resolves" do
      expect(described_class.handler_for("story_insights")).to eq(InstagramConnect::Ingest::Handlers::Unknown)
    end
  end

  describe ".handled?" do
    it "distinguishes a field with a handler from one that only banks" do
      expect(described_class.handled?("comments")).to be(true)
      expect(described_class.handled?("mentions")).to be(false)
    end
  end

  describe ".subscribable_fields" do
    # Subscribing to a field the gem cannot parse yet is deliberate: the events
    # bank and replay later, whereas an unsubscribed field is lost for good.
    it "covers every field the gem knows about, not only the handled ones" do
      expect(described_class.subscribable_fields).to include(*described_class.handled_fields)
      expect(described_class.subscribable_fields).to include("mentions", "story_insights")
    end

    it "lists no field twice" do
      expect(described_class.subscribable_fields.uniq).to eq(described_class.subscribable_fields)
    end
  end
end

require "rails_helper"

RSpec.describe "messaging event ingest" do
  let!(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "t")
  end
  let(:config) { InstagramConnect.configuration }

  def run(event, time: 1_700_000_001_000)
    payload = {
      "object" => "instagram",
      "entry" => [ { "id" => "IGACC", "time" => time, "messaging" => [ event.merge("timestamp" => time) ] } ]
    }
    InstagramConnect::Ingest::Dispatcher.new(config).call(payload)
  end

  def conversation_for(igsid = "CUST")
    InstagramConnect::Conversation.find_by(account_id: account.id, igsid: igsid)
  end

  def inbound_message(mid:, at: 1_700_000_000_000)
    run({ "sender" => { "id" => "CUST" }, "recipient" => { "id" => "IGACC" },
          "message" => { "mid" => mid, "text" => "hi" } }, time: at)
    InstagramConnect::Message.find_by(ig_message_id: mid)
  end

  describe "reactions" do
    def reaction_event(mid:, action: "react", emoji: "❤️", sender: "CUST")
      { "sender" => { "id" => sender }, "recipient" => { "id" => "IGACC" },
        "reaction" => { "mid" => mid, "action" => action, "reaction" => "love", "emoji" => emoji } }
    end

    it "logs the reaction and projects it onto the message" do
      message = inbound_message(mid: "m1")

      run(reaction_event(mid: "m1"))

      reaction = InstagramConnect::MessageReaction.last
      expect(reaction.message).to eq(message)
      expect(reaction.actor).to eq("customer")
      expect(reaction.reaction).to eq("love")
      expect(message.reload.reactions_count).to eq(1)
      expect(message.last_reaction).to eq("love")
    end

    it "records a reaction the business left as its own" do
      inbound_message(mid: "m1")

      run(reaction_event(mid: "m1", sender: "IGACC"))

      expect(InstagramConnect::MessageReaction.last.actor).to eq("business")
    end

    # react then unreact then react is one mid three times. Keying the ledger on
    # the mid alone would swallow the second and third as duplicates.
    it "keeps react, unreact and re-react as separate events" do
      inbound_message(mid: "m1")

      run(reaction_event(mid: "m1"), time: 1_700_000_002_000)
      run(reaction_event(mid: "m1", action: "unreact"), time: 1_700_000_003_000)
      run(reaction_event(mid: "m1"), time: 1_700_000_004_000)

      expect(InstagramConnect::MessageReaction.count).to eq(3)
      expect(InstagramConnect::Message.find_by(ig_message_id: "m1").last_reaction).to eq("love")
    end

    it "clears the projection when the last event was an unreact" do
      message = inbound_message(mid: "m1")

      run(reaction_event(mid: "m1"), time: 1_700_000_002_000)
      run(reaction_event(mid: "m1", action: "unreact"), time: 1_700_000_003_000)

      expect(message.reload.last_reaction).to be_nil
      expect(message.reactions_count).to eq(1)
    end

    # Meta guarantees no ordering, so the reaction can beat its message.
    it "stores a reaction for a message it has never seen" do
      run(reaction_event(mid: "unknown-mid"))

      reaction = InstagramConnect::MessageReaction.last
      expect(reaction.message).to be_nil
      expect(reaction.ig_message_id).to eq("unknown-mid")
      expect(conversation_for).to be_present
    end

    it "counts as thread activity, because a reaction reopens Meta's 24-hour window" do
      inbound_message(mid: "m1")

      run(reaction_event(mid: "m1"), time: 1_700_000_009_000)

      expect(conversation_for.last_event_at.to_i).to eq(1_700_000_009)
    end
  end

  describe "read receipts" do
    it "records the receipt and marks earlier outbound messages seen" do
      conversation = InstagramConnect::Conversation.locate(account: account, igsid: "CUST")
      sent = conversation.messages.create!(direction: "outbound", status: "sent", kind: "dm",
                                           body: "hello", sent_at: Time.at(1_700_000_000).utc)

      run({ "sender" => { "id" => "CUST" }, "read" => { "mid" => "m9" } }, time: 1_700_000_005_000)

      expect(conversation.reload.customer_last_read_mid).to eq("m9")
      expect(conversation.customer_last_read_at.to_i).to eq(1_700_000_005)
      expect(sent.reload.seen_at.to_i).to eq(1_700_000_005)
    end

    it "leaves a message sent after the receipt unseen" do
      conversation = InstagramConnect::Conversation.locate(account: account, igsid: "CUST")
      later = conversation.messages.create!(direction: "outbound", status: "sent", kind: "dm",
                                            body: "after", sent_at: Time.at(1_700_000_009).utc)

      run({ "sender" => { "id" => "CUST" }, "read" => { "mid" => "m9" } }, time: 1_700_000_005_000)

      expect(later.reload.seen_at).to be_nil
    end

    # A receipt redelivered after a newer one must not roll the thread back.
    it "never moves the read marker backwards" do
      run({ "sender" => { "id" => "CUST" }, "read" => { "mid" => "new" } }, time: 1_700_000_009_000)
      run({ "sender" => { "id" => "CUST" }, "read" => { "mid" => "old" } }, time: 1_700_000_001_000)

      conversation = conversation_for
      expect(conversation.customer_last_read_mid).to eq("new")
      expect(conversation.customer_last_read_at.to_i).to eq(1_700_000_009)
    end
  end

  describe "referrals" do
    it "records where the customer came from and counts as activity" do
      run({ "sender" => { "id" => "CUST" }, "recipient" => { "id" => "IGACC" },
            "referral" => { "ref" => "summer-campaign", "source" => "ADS", "type" => "OPEN_THREAD" } })

      conversation = conversation_for
      expect(conversation.last_referral_ref).to eq("summer-campaign")
      expect(conversation.last_event_at.to_i).to eq(1_700_000_001)
    end

    # A referral inside a message belongs to that message, not to a referral
    # event of its own — otherwise one arrival is counted twice.
    it "keeps a referral nested in a message on the message" do
      run({ "sender" => { "id" => "CUST" }, "recipient" => { "id" => "IGACC" },
            "message" => { "mid" => "m1", "text" => "hi",
                           "referral" => { "ref" => "inline", "source" => "IG_LINK" } } })

      expect(InstagramConnect::Message.last.referral_ref).to eq("inline")
      expect(InstagramConnect::WebhookEvent.last.field).to eq("messages")
    end
  end

  describe "opt-ins" do
    it "counts as thread activity and banks the token for the host to read" do
      run({ "sender" => { "id" => "CUST" }, "optin" => { "type" => "notification_messages",
                                                        "notification_messages_token" => "tok" } })

      expect(conversation_for.last_event_at.to_i).to eq(1_700_000_001)
      expect(InstagramConnect::WebhookEvent.last.payload.dig("optin", "notification_messages_token"))
        .to eq("tok")
    end
  end

  describe "thread handover" do
    it "records which app took control, so a send can refuse rather than fail opaquely" do
      run({ "sender" => { "id" => "CUST" },
            "pass_thread_control" => { "new_owner_app_id" => "263902037430900" } })

      conversation = conversation_for
      expect(conversation.thread_owner_app_id).to eq("263902037430900")
      expect(conversation).to be_controlled_elsewhere
    end

    it "records a take with no named owner" do
      run({ "sender" => { "id" => "CUST" }, "take_thread_control" => {} })

      expect(conversation_for.thread_control_at).to be_present
      expect(conversation_for).not_to be_controlled_elsewhere
    end

    it "ignores a handover event that names no control key" do
      key = InstagramConnect::Ingest::Handlers::MessagingHandover.dedupe_key("sender" => { "id" => "CUST" })

      expect(key).to be_nil
    end

    it "never applies an older handover over a newer one" do
      run({ "sender" => { "id" => "CUST" }, "pass_thread_control" => { "new_owner_app_id" => "new" } },
          time: 1_700_000_009_000)
      run({ "sender" => { "id" => "CUST" }, "pass_thread_control" => { "new_owner_app_id" => "old" } },
          time: 1_700_000_001_000)

      expect(conversation_for.thread_owner_app_id).to eq("new")
    end
  end

  describe "message fields from the wire" do
    it "stores the reply target, quick reply payload and story it came from" do
      run({ "sender" => { "id" => "CUST" }, "recipient" => { "id" => "IGACC" },
            "message" => {
              "mid" => "m1", "text" => "yes please",
              "reply_to" => { "mid" => "earlier" },
              "quick_reply" => { "payload" => "BOOK_NOW" },
              "attachments" => [ { "type" => "story_mention",
                                   "payload" => { "url" => "https://cdn.example/s.jpg",
                                                  "story" => { "id" => "story-1", "url" => "https://ig/s" } } } ]
            } })

      message = InstagramConnect::Message.last
      expect(message.reply_to_mid).to eq("earlier")
      expect(message.quick_reply_payload).to eq("BOOK_NOW")
      expect(message.story_id).to eq("story-1")
      expect(message.media_kind).to eq("story_mention")
    end

    it "creates one attachment row per file and a fetch job for each fetchable one" do
      run({ "sender" => { "id" => "CUST" }, "recipient" => { "id" => "IGACC" },
            "message" => { "mid" => "m1", "attachments" => [
              { "type" => "image", "payload" => { "url" => "https://cdn.example/1.jpg" } },
              { "type" => "video", "payload" => { "url" => "https://cdn.example/2.mp4" } },
              { "type" => "share", "payload" => {} }
            ] } })

      attachments = InstagramConnect::Message.last.attachments
      expect(attachments.map(&:position)).to eq([ 0, 1, 2 ])
      expect(attachments.map(&:kind)).to eq(%w[image video share])
      # The one with nothing to fetch is skipped rather than left pending, so it
      # never renders as a placeholder waiting on bytes that will not arrive.
      expect(attachments.map(&:state)).to eq(%w[pending pending skipped])

      # One job per attachment, so a ten-image message does not serialise behind
      # whichever file is slowest.
      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs
        .select { |job| job[:job] == InstagramConnect::FetchMediaJob }
      expect(enqueued.size).to eq(2)
    end

    it "keeps an unsent message as a row rather than destroying the thread's shape" do
      run({ "sender" => { "id" => "CUST" }, "recipient" => { "id" => "IGACC" },
            "message" => { "mid" => "m1", "text" => "oops", "is_deleted" => true } })

      expect(InstagramConnect::Message.last.deleted_at).to be_present
    end

    it "marks an unsupported message as such, with nothing to fetch" do
      run({ "sender" => { "id" => "CUST" }, "recipient" => { "id" => "IGACC" },
            "message" => { "mid" => "m1", "is_unsupported" => true } })

      message = InstagramConnect::Message.last
      expect(message.unsupported).to be(true)
      expect(message.media_status).to eq("unavailable")
    end

    # The whole point of sent_at: a batch delayed by a redeploy must not stamp
    # old messages as the newest thing in the thread.
    it "orders the thread by Meta's clock, not by when we stored it" do
      inbound_message(mid: "later", at: 1_700_000_500_000)
      inbound_message(mid: "earlier", at: 1_700_000_100_000)

      expect(conversation_for.last_message_at.to_i).to eq(1_700_000_500)
      expect(conversation_for.last_message_preview).to eq("hi")
    end
  end
end

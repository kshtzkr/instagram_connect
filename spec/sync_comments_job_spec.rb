require "rails_helper"

RSpec.describe InstagramConnect::SyncCommentsJob do
  let(:base) { "https://graph.facebook.com/v21.0" }
  let(:json) { { "Content-Type" => "application/json" } }

  let!(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGUSER", auth_path: "facebook_login",
                                      access_token: "tok", page_id: "PAGE1", active: true)
  end

  def comments_page(items)
    stub_request(:get, "#{base}/MEDIA1/comments").with(query: hash_including({}))
      .to_return(status: 200, body: { data: items }.to_json, headers: json)
  end

  it "imports a post's existing comments with author, time, likes and replies" do
    comments_page([
      { id: "c-1", text: "How much for Nubra?", username: "traveller_asha",
        from: { id: "IG123", username: "traveller_asha" },
        timestamp: "2026-07-21T10:00:00+0000", like_count: 3,
        replies: { data: [
          { id: "c-1-r", text: "DM'd you!", username: "escapes.asia",
            timestamp: "2026-07-21T11:00:00+0000" }
        ] } },
      { id: "c-2", text: "Interested", username: "other", hidden: true }
    ])

    described_class.perform_now(account.id, "MEDIA1")

    top = InstagramConnect::Comment.find_by(comment_id: "c-1")
    expect(top.text).to eq("How much for Nubra?")
    expect(top.from_username).to eq("traveller_asha")
    expect(top.from_ig_id).to eq("IG123")
    expect(top.media_id).to eq("MEDIA1")
    expect(top.like_count).to eq(3)
    expect(top.commented_at).to be_present
    expect(top.parent_id).to be_nil

    reply = InstagramConnect::Comment.find_by(comment_id: "c-1-r")
    expect(reply.parent_id).to eq("c-1")
    expect(reply.text).to eq("DM'd you!")

    expect(InstagramConnect::Comment.find_by(comment_id: "c-2").hidden_at).to be_present
  end

  it "follows Meta's hidden state both ways without clobbering the first hidden time" do
    comments_page([ { id: "c-h", text: "rude", hidden: true } ])
    described_class.perform_now(account.id, "MEDIA1")
    first_hidden_at = InstagramConnect::Comment.find_by(comment_id: "c-h").hidden_at

    described_class.perform_now(account.id, "MEDIA1")
    expect(InstagramConnect::Comment.find_by(comment_id: "c-h").hidden_at).to eq(first_hidden_at)

    comments_page([ { id: "c-h", text: "rude", hidden: false } ])
    described_class.perform_now(account.id, "MEDIA1")
    expect(InstagramConnect::Comment.find_by(comment_id: "c-h").hidden_at).to be_nil
  end

  it "enriches a webhook-created row instead of duplicating it" do
    InstagramConnect::Comment.record(account: account, comment_id: "c-1", media_id: "MEDIA1",
                                     text: "How much for Nubra?", from_username: "traveller_asha")
    comments_page([ { id: "c-1", text: "How much for Nubra?", username: "traveller_asha",
                      from: { id: "IG123" }, timestamp: "2026-07-21T10:00:00+0000" } ])

    described_class.perform_now(account.id, "MEDIA1")

    rows = InstagramConnect::Comment.where(comment_id: "c-1")
    expect(rows.count).to eq(1)
    expect(rows.first.from_ig_id).to eq("IG123")
    expect(rows.first.commented_at).to be_present
  end

  # from{...} and parent_id are Facebook-comment fields: one refused field
  # fails the whole Instagram call with (#100) and zero comments import. The
  # request must carry only the documented Instagram-comment fields; the
  # upsert still uses from/parent_id opportunistically when Meta sends them.
  it "requests only fields Instagram comments actually support" do
    comments_page([])

    described_class.perform_now(account.id, "MEDIA1")

    expect(WebMock).to have_requested(:get, "#{base}/MEDIA1/comments")
      .with(query: hash_including("fields" => described_class::COMMENT_FIELDS))
    expect(described_class::COMMENT_FIELDS).not_to include("from")
    expect(described_class::COMMENT_FIELDS).not_to include("parent_id")
  end

  it "logs loudly and stores nothing when the walk fails" do
    stub_request(:get, "#{base}/MEDIA1/comments").with(query: hash_including({}))
      .to_return(status: 400, body: { error: { message: "nope", code: 100 } }.to_json,
                 headers: json)

    expect(Rails.logger).to receive(:error).with(/comment sync failed for account=#{account.id}/)
    described_class.perform_now(account.id, "MEDIA1")

    expect(InstagramConnect::Comment.count).to eq(0)
  end

  it "does nothing for a missing or inactive account" do
    account.update!(active: false)

    described_class.perform_now(account.id, "MEDIA1")
    described_class.perform_now(0, "MEDIA1")

    expect(WebMock).not_to have_requested(:get, "#{base}/MEDIA1/comments")
  end

  it "throttles screen-driven enqueues per post" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

    expect {
      described_class.enqueue_throttled(account, "MEDIA1")
      described_class.enqueue_throttled(account, "MEDIA1")
      described_class.enqueue_throttled(account, "MEDIA2")
    }.to have_enqueued_job(described_class).exactly(:twice)
  end

  it "survives an unparseable timestamp" do
    comments_page([ { id: "c-t", text: "hi", timestamp: "2026-13-45T99:99:99" } ])

    described_class.perform_now(account.id, "MEDIA1")

    expect(InstagramConnect::Comment.find_by(comment_id: "c-t").commented_at).to be_nil
  end
  describe "long reply threads" do
    it "walks the replies edge when the inline expansion says there is more" do
      comments_page([ { id: "c-busy", text: "top",
                        replies: { data: [ { id: "r-1", text: "first inline" } ],
                                   paging: { next: "https://graph/next" } } } ])
      stub_request(:get, "#{base}/c-busy/replies").with(query: hash_including({}))
        .to_return(status: 200,
                   body: { data: [ { id: "r-2", text: "from the walk" },
                                   { id: "r-3", text: "tail reply" } ] }.to_json,
                   headers: json)

      described_class.perform_now(account.id, "MEDIA1")

      expect(InstagramConnect::Comment.where(parent_id: "c-busy").count).to eq(3)
      expect(InstagramConnect::Comment.find_by(comment_id: "r-3").text).to eq("tail reply")
    end

    it "does not walk when the inline page was the whole thread" do
      comments_page([ { id: "c-small", text: "top",
                        replies: { data: [ { id: "r-only", text: "one reply" } ] } } ])

      described_class.perform_now(account.id, "MEDIA1")

      expect(WebMock).not_to have_requested(:get, %r{/c-small/replies})
      expect(InstagramConnect::Comment.where(parent_id: "c-small").count).to eq(1)
    end

    it "keeps the inline replies when the overflow walk fails" do
      comments_page([ { id: "c-flaky", text: "top",
                        replies: { data: [ { id: "r-kept", text: "kept" } ],
                                   paging: { next: "https://graph/next" } } } ])
      stub_request(:get, "#{base}/c-flaky/replies").with(query: hash_including({}))
        .to_return(status: 400, body: { error: { message: "nope", code: 1 } }.to_json,
                   headers: json)

      expect(Rails.logger).to receive(:error).with(/replies walk failed for comment=c-flaky/)
      described_class.perform_now(account.id, "MEDIA1")

      expect(InstagramConnect::Comment.find_by(comment_id: "r-kept")).to be_present
    end
  end

  # The 2026-07-28 live failure: a comment made minutes earlier arrived via
  # the sweep (not its webhook) and the automation never fired — the on_comment
  # hook only lived on the webhook path. A fresh comment is fully actionable
  # for 7 days, so the sweep announces it too; history stays silent.
  describe "announcing fresh imports to the host" do
    around do |example|
      previous = InstagramConnect.configuration.on_comment
      example.run
    ensure
      InstagramConnect.configuration.on_comment = previous
    end

    it "fires on_comment once for a newly imported fresh comment" do
      seen = []
      InstagramConnect.configuration.on_comment = ->(comment) { seen << comment.comment_id }
      comments_page([ { id: "c-fresh", text: "I love bali can I get the itinerary",
                        username: "kshtzkr",
                        timestamp: 10.minutes.ago.iso8601 } ])

      described_class.perform_now(account.id, "MEDIA1")
      described_class.perform_now(account.id, "MEDIA1")

      expect(seen).to eq([ "c-fresh" ])
    end

    it "stays silent for history older than the fresh window" do
      seen = []
      InstagramConnect.configuration.on_comment = ->(comment) { seen << comment.comment_id }
      comments_page([ { id: "c-old", text: "bali!", timestamp: 3.days.ago.iso8601 } ])

      described_class.perform_now(account.id, "MEDIA1")

      expect(seen).to be_empty
    end

    it "stays silent when enriching a row the webhook already created" do
      InstagramConnect::Comment.record(account: account, comment_id: "c-hooked",
                                       media_id: "MEDIA1", text: "bali",
                                       from_username: "asha")
      seen = []
      InstagramConnect.configuration.on_comment = ->(comment) { seen << comment.comment_id }
      comments_page([ { id: "c-hooked", text: "bali", username: "asha",
                        timestamp: 5.minutes.ago.iso8601 } ])

      described_class.perform_now(account.id, "MEDIA1")

      expect(seen).to be_empty
    end

    it "keeps walking when the host callback explodes" do
      InstagramConnect.configuration.on_comment = ->(_c) { raise "host bug" }
      comments_page([ { id: "c-1", text: "bali", timestamp: 5.minutes.ago.iso8601 },
                      { id: "c-2", text: "goa", timestamp: 5.minutes.ago.iso8601 } ])

      described_class.perform_now(account.id, "MEDIA1")

      expect(InstagramConnect::Comment.where(comment_id: %w[c-1 c-2]).count).to eq(2)
    end

    it "does nothing when no callback is configured" do
      InstagramConnect.configuration.on_comment = nil
      comments_page([ { id: "c-3", text: "bali", timestamp: 5.minutes.ago.iso8601 } ])

      expect { described_class.perform_now(account.id, "MEDIA1") }.not_to raise_error
    end
  end

end

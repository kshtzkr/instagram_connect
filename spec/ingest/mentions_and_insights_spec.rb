require "rails_helper"

RSpec.describe "mentions, comments and story insights" do
  let!(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "t")
  end
  let(:config) { InstagramConnect.configuration }

  def run(field, value, time: 1_700_000_001_000)
    payload = {
      "object" => "instagram",
      "entry" => [ { "id" => "IGACC", "time" => time,
                     "changes" => [ { "field" => field, "value" => value } ] } ]
    }
    InstagramConnect::Ingest::Dispatcher.new(config).call(payload)
  end

  describe "mentions" do
    # Meta does not store mention notifications and never re-delivers them, so
    # the handler is the single point at which the event becomes a row or stops
    # existing. For a travel brand these are the highest-value events on the
    # platform: customers posting photos of a trip we sold them.
    it "records a mention in a comment" do
      summary = run("mentions", { "media_id" => "media-1", "comment_id" => "c-1",
                                  "text" => "loved it @escapes.asia",
                                  "from" => { "username" => "traveller" } })

      expect(summary[:unhandled]).to eq(0)
      mention = InstagramConnect::Mention.last
      expect(mention.kind).to eq("comment")
      expect(mention.comment_id).to eq("c-1")
      expect(mention.from_username).to eq("traveller")
      expect(mention.mentioned_at.to_i).to eq(1_700_000_001)
      expect(mention).not_to be_answered
    end

    it "records a mention in a caption, where there is no comment" do
      run("mentions", { "media_id" => "media-2", "text" => "with @escapes.asia" })

      expect(InstagramConnect::Mention.last.kind).to eq("caption")
    end

    # The mentioning post is almost always one we have never seen — it belongs
    # to the customer, not to us.
    it "creates the media it refers to" do
      run("mentions", { "media_id" => "media-3", "comment_id" => "c-3" })

      expect(InstagramConnect::MediaItem.find_by(ig_media_id: "media-3")).to be_present
    end

    it "treats a redelivery of the same mention as a duplicate" do
      value = { "media_id" => "media-4", "comment_id" => "c-4" }

      run("mentions", value)
      summary = run("mentions", value)

      expect(summary[:duplicates]).to eq(1)
      expect(InstagramConnect::Mention.count).to eq(1)
    end

    it "banks a mention carrying no media id rather than storing a useless row" do
      summary = run("mentions", { "text" => "hi" })

      expect(summary[:unhandled]).to eq(1)
      expect(InstagramConnect::Mention.count).to eq(0)
    end
  end

  describe "story insights" do
    let(:metrics) { { "impressions" => 120, "reach" => 98, "replies" => 3, "taps_forward" => 40 } }

    # Story metrics are retrievable for 24 hours and then cease to exist
    # anywhere. The webhook fires as the story expires and carries the final
    # numbers, so this write happens inside ingest rather than in a job that
    # might be delayed past the point of no return.
    it "writes the final metrics as a snapshot the moment they arrive" do
      run("story_insights", metrics.merge("media_id" => "story-1"))

      snapshot = InstagramConnect::InsightSnapshot.last
      expect(snapshot.subject_type).to eq("story")
      expect(snapshot.subject_ref).to eq("story-1")
      expect(snapshot.source).to eq("webhook")
      expect(snapshot.period).to eq("lifetime")
      expect(snapshot.value("reach")).to eq(98)
      expect(snapshot).not_to be_empty
    end

    it "creates the story's media row, which may have been posted from a phone" do
      run("story_insights", metrics.merge("media_id" => "story-2"))

      media = InstagramConnect::MediaItem.find_by(ig_media_id: "story-2")
      expect(media).to be_present
      expect(media).to be_story
    end

    # Meta omits a metric it will not report rather than sending a zero, and a
    # UI has to be able to tell those apart.
    it "marks a reading with no metrics empty rather than inventing zeroes" do
      run("story_insights", { "media_id" => "story-3" })

      snapshot = InstagramConnect::InsightSnapshot.last
      expect(snapshot).to be_empty
      expect(snapshot.value("reach")).to be_nil
    end

    it "banks an insight event with no media id" do
      summary = run("story_insights", metrics)

      expect(summary[:unhandled]).to eq(1)
      expect(InstagramConnect::InsightSnapshot.count).to eq(0)
    end
  end

  describe "comments" do
    def comment_value(id: "c-1")
      { "id" => id, "text" => "how much?", "media" => { "id" => "media-9" },
        "from" => { "id" => "ig-user-1", "username" => "asker" } }
    end

    it "captures the commenter's id, which is what a private reply needs" do
      run("comments", comment_value)

      comment = InstagramConnect::Comment.last
      expect(comment.from_ig_id).to eq("ig-user-1")
      expect(comment.commented_at.to_i).to eq(1_700_000_001)
      expect(comment.is_live).to be(false)
    end

    # A private reply to a live comment is valid only while the broadcast runs,
    # so this flag is what stops a UI offering a button certain to fail.
    it "marks a live comment as such" do
      run("live_comments", comment_value(id: "c-live"))

      expect(InstagramConnect::Comment.find_by(comment_id: "c-live").is_live).to be(true)
    end

    it "records the media the comment was left on" do
      run("comments", comment_value)

      expect(InstagramConnect::MediaItem.find_by(ig_media_id: "media-9")).to be_present
    end

    it "does not invent a media row when the comment names none" do
      run("comments", { "id" => "c-2", "text" => "hi" })

      expect(InstagramConnect::MediaItem.count).to eq(0)
    end
  end
end

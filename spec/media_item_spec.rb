require "rails_helper"

RSpec.describe "media, mentions and snapshots" do
  let(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "t")
  end

  describe InstagramConnect::MediaItem do
    it "upserts by Meta's id so whichever path arrives first wins" do
      described_class.record(account: account, ig_media_id: "m1", caption: "first")
      described_class.record(account: account, ig_media_id: "m1", media_product_type: "STORY")

      expect(described_class.count).to eq(1)
      media = described_class.last
      expect(media.caption).to eq("first")
      expect(media).to be_story
    end

    # Two webhooks about the same post can land at once — a comment and a
    # mention, say — and both will try to create the media row.
    it "survives losing the race to another writer" do
      described_class.record(account: account, ig_media_id: "m2")
      allow_any_instance_of(described_class).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)

      expect(described_class.record(account: account, ig_media_id: "m2").ig_media_id).to eq("m2")
    end
  end

  describe InstagramConnect::Mention do
    def record(**overrides)
      described_class.record(**{ account: account, kind: "comment", ig_media_id: "m1",
                                comment_id: "c1", mentioned_at: Time.current }.merge(overrides))
    end

    it "upserts on the media and comment pair" do
      record(text: "first")
      record(text: "second")

      expect(described_class.count).to eq(1)
      expect(described_class.last.text).to eq("second")
    end

    it "survives losing the race to another writer" do
      record
      allow_any_instance_of(described_class).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)

      expect(record.comment_id).to eq("c1")
    end

    it "lists the ones still waiting for a reply, newest first" do
      old = record(comment_id: "c-old", mentioned_at: 2.days.ago)
      recent = record(comment_id: "c-new", mentioned_at: 1.hour.ago)
      record(comment_id: "c-done", replied_at: Time.current)

      expect(described_class.unanswered.recent).to eq([ recent, old ])
      expect(described_class.find_by(comment_id: "c-done")).to be_answered
    end
  end

  describe InstagramConnect::InsightSnapshot do
    def record(**overrides)
      described_class.record(**{ account: account, subject_type: "story", subject_ref: "s1",
                                period: "lifetime", period_start: Date.current,
                                metrics: { "reach" => 10 }, captured_at: Time.current }.merge(overrides))
    end

    # The poller overwrites its own reading as a story accrues views; the
    # webhook's final reading is a separate row because source is part of the
    # key, so a dropped webhook still leaves the last mid-life reading behind.
    it "keeps API and webhook readings of the same story apart" do
      record(source: "api", metrics: { "reach" => 10 })
      record(source: "api", metrics: { "reach" => 40 })
      record(source: "webhook", metrics: { "reach" => 98 })

      expect(described_class.count).to eq(2)
      expect(described_class.find_by(source: "api").value("reach")).to eq(40)
      expect(described_class.find_by(source: "webhook").value("reach")).to eq(98)
    end

    # nil means Meta did not report the metric, which is not zero. Callers must
    # never be able to reach for a default.
    it "returns nil for a metric that was not reported" do
      expect(record.value("saved")).to be_nil
    end

    it "returns nil rather than raising when the payload is not a hash" do
      snapshot = record
      snapshot.update_column(:metrics, [])

      expect(snapshot.reload.value("reach")).to be_nil
    end

    it "rejects a subject type or source it does not recognise" do
      snapshot = described_class.new(account: account, subject_type: "planet", source: "carrier-pigeon",
                                     period: "day", period_start: Date.current,
                                     metrics: {}, captured_at: Time.current)

      expect(snapshot).not_to be_valid
      expect(snapshot.errors.attribute_names).to include(:subject_type, :source)
    end
  end
end

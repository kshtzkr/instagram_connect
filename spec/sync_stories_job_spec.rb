require "rails_helper"

RSpec.describe InstagramConnect::SyncStoriesJob do
  let(:base) { "https://graph.facebook.com/v21.0" }
  let(:json) { { "Content-Type" => "application/json" } }

  let!(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGUSER", auth_path: "facebook_login",
                                      access_token: "tok", page_id: "PAGE1", active: true)
  end

  def stories(items)
    stub_request(:get, "#{base}/IGUSER/stories").with(query: hash_including({}))
      .to_return(status: 200, body: { data: items }.to_json, headers: json)
  end

  it "mirrors live stories as STORY media rows" do
    stories([ { id: "s-1", media_type: "VIDEO", media_product_type: "STORY",
                media_url: "https://cdn/story.mp4", thumbnail_url: "https://cdn/story.jpg",
                timestamp: "2026-07-27T08:00:00+0000" } ])

    described_class.perform_now(account.id)

    item = InstagramConnect::MediaItem.find_by(ig_media_id: "s-1")
    expect(item.media_product_type).to eq("STORY")
    expect(item.media_url).to eq("https://cdn/story.mp4")
    expect(item.posted_at).to be_present
    expect(item).to be_story
  end

  it "stamps STORY even when Meta omits media_product_type" do
    stories([ { id: "s-2", media_type: "IMAGE" } ])

    described_class.perform_now(account.id)

    expect(InstagramConnect::MediaItem.find_by(ig_media_id: "s-2").media_product_type)
      .to eq("STORY")
  end

  it "keeps expired stories: a story absent from the listing is never touched" do
    old_story = InstagramConnect::MediaItem.record(
      account: account, ig_media_id: "s-old", media_product_type: "STORY",
      posted_at: 3.days.ago
    )
    stories([])

    described_class.perform_now(account.id)

    expect(InstagramConnect::MediaItem.find_by(ig_media_id: "s-old")).to eq(old_story)
    expect(old_story.reload.removed_from_instagram_at).to be_nil
  end

  it "upserts rather than duplicates on re-run" do
    stories([ { id: "s-1", media_type: "IMAGE", caption: "v1" } ])
    described_class.perform_now(account.id)
    stories([ { id: "s-1", media_type: "IMAGE", caption: "v2" } ])
    described_class.perform_now(account.id)

    rows = InstagramConnect::MediaItem.where(ig_media_id: "s-1")
    expect(rows.count).to eq(1)
    expect(rows.first.caption).to eq("v2")
  end

  it "logs loudly and stores nothing when the listing fails" do
    stub_request(:get, "#{base}/IGUSER/stories").with(query: hash_including({}))
      .to_return(status: 400, body: { error: { message: "nope", code: 100 } }.to_json,
                 headers: json)

    expect(Rails.logger).to receive(:error).with(/stories sync failed for account=#{account.id}/)
    described_class.perform_now(account.id)

    expect(InstagramConnect::MediaItem.count).to eq(0)
  end

  it "does nothing for a missing or inactive account" do
    account.update!(active: false)

    described_class.perform_now(account.id)
    described_class.perform_now(0)

    expect(WebMock).not_to have_requested(:get, "#{base}/IGUSER/stories")
  end

  it "throttles screen-driven enqueues through the cache" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

    expect {
      described_class.enqueue_throttled(account)
      described_class.enqueue_throttled(account)
    }.to have_enqueued_job(described_class).exactly(:once)
  end

  it "handles a garbage timestamp without dying" do
    stories([ { id: "s-3", media_type: "IMAGE", timestamp: "2026-13-45T99:99:99" } ])

    described_class.perform_now(account.id)

    expect(InstagramConnect::MediaItem.find_by(ig_media_id: "s-3").posted_at).to be_nil
  end
end

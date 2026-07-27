require "rails_helper"

RSpec.describe InstagramConnect::SyncMediaJob do
  let(:base) { "https://graph.facebook.com/v21.0" }
  let(:json) { { "Content-Type" => "application/json" } }

  let!(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGUSER", auth_path: "facebook_login",
                                      access_token: "tok", page_id: "PAGE1", active: true)
  end

  def single_page(items)
    stub_request(:get, "#{base}/IGUSER/media").with(query: hash_including({}))
      .to_return(status: 200, body: { data: items }.to_json, headers: json)
  end

  it "fills in what each post is, including engagement and the poster frame" do
    single_page([ { id: "m-1", media_type: "REELS", caption: "Land in Hanoi",
                    permalink: "https://www.instagram.com/reel/abc/",
                    media_url: "https://cdn/video.mp4",
                    thumbnail_url: "https://cdn/poster.jpg",
                    like_count: 143, comments_count: 37,
                    timestamp: "2026-04-22T10:00:00+0000" } ])

    described_class.perform_now(account.id)

    item = InstagramConnect::MediaItem.find_by(ig_media_id: "m-1")
    expect(item.caption).to eq("Land in Hanoi")
    expect(item.permalink).to eq("https://www.instagram.com/reel/abc/")
    expect(item.thumbnail_url).to eq("https://cdn/poster.jpg")
    expect(item.like_count).to eq(143)
    expect(item.comments_count).to eq(37)
    expect(item.posted_at).to be_present
  end

  it "keeps a carousel's slides so a host can render every frame" do
    single_page([ { id: "m-car", media_type: "CAROUSEL_ALBUM", media_product_type: "FEED",
                    caption: "Five frames",
                    children: { data: [
                      { id: "c-1", media_type: "IMAGE", media_url: "https://cdn/1.jpg" },
                      { id: "c-2", media_type: "VIDEO", media_url: "https://cdn/2.mp4",
                        thumbnail_url: "https://cdn/2.jpg" }
                    ] } } ])

    described_class.perform_now(account.id)

    item = InstagramConnect::MediaItem.find_by(ig_media_id: "m-car")
    expect(item.media_product_type).to eq("FEED")
    expect(item.children.length).to eq(2)
    expect(item.children.last).to include("media_type" => "VIDEO",
                                          "media_url" => "https://cdn/2.mp4",
                                          "thumbnail_url" => "https://cdn/2.jpg")
  end

  it "asks Meta for the engagement fields" do
    single_page([])

    described_class.perform_now(account.id)

    expect(WebMock).to have_requested(:get, "#{base}/IGUSER/media")
      .with(query: hash_including("fields" => a_string_matching(
        /like_count,comments_count,media_product_type,children\{/
      )))
  end

  it "updates rather than duplicates a post it has seen before" do
    InstagramConnect::MediaItem.record(account: account, ig_media_id: "m-1")
    single_page([ { id: "m-1", caption: "now with a caption" } ])

    expect { described_class.perform_now(account.id) }
      .not_to change(InstagramConnect::MediaItem, :count)
    expect(InstagramConnect::MediaItem.find_by(ig_media_id: "m-1").caption)
      .to eq("now with a caption")
  end

  describe "the full-history mirror" do
    # Instagram sends no webhook for a deleted post; absence from a COMPLETED
    # walk is the only signal. The row is stamped, never destroyed.
    it "marks a known post that vanished, and keeps the row" do
      gone = InstagramConnect::MediaItem.record(account: account, ig_media_id: "m-gone",
                                               synced_at: 1.day.ago)
      single_page([ { id: "m-still-here" } ])

      described_class.perform_now(account.id, full: true)

      expect(gone.reload).to be_removed
      expect(InstagramConnect::MediaItem.find_by(ig_media_id: "m-still-here")).not_to be_removed
    end

    it "un-grays a post that reappears" do
      InstagramConnect::MediaItem.record(account: account, ig_media_id: "m-1")
        .update!(removed_from_instagram_at: 1.day.ago)
      single_page([ { id: "m-1" } ])

      described_class.perform_now(account.id, full: true)

      expect(InstagramConnect::MediaItem.find_by(ig_media_id: "m-1")).not_to be_removed
    end

    # A failed or partial walk proves nothing about absence; marking from it
    # would gray live posts.
    it "marks nothing when the walk fails" do
      existing = InstagramConnect::MediaItem.record(account: account, ig_media_id: "m-1",
                                                    synced_at: 1.day.ago)
      stub_request(:get, "#{base}/IGUSER/media").with(query: hash_including({}))
        .to_return(status: 400, body: { error: { message: "rate limited" } }.to_json, headers: json)

      described_class.perform_now(account.id, full: true)

      expect(existing.reload).not_to be_removed
    end

    it "never marks another account's posts" do
      other = InstagramConnect::Account.create!(ig_user_id: "OTHER", auth_path: "facebook_login",
                                                access_token: "t2")
      theirs = InstagramConnect::MediaItem.record(account: other, ig_media_id: "m-theirs",
                                                  synced_at: 1.day.ago)
      single_page([ { id: "m-mine" } ])

      described_class.perform_now(account.id, full: true)

      expect(theirs.reload).not_to be_removed
    end

    it "walks with cursors across pages" do
      stub_request(:get, "#{base}/IGUSER/media")
        .with(query: hash_including({}))
        .to_return(
          { status: 200, headers: json,
            body: { data: [ { id: "m-1" } ],
                    paging: { cursors: { after: "CURSOR" }, next: "next-url" } }.to_json },
          { status: 200, headers: json, body: { data: [ { id: "m-2" } ] }.to_json }
        )

      described_class.perform_now(account.id, full: true)

      expect(InstagramConnect::MediaItem.where(ig_media_id: %w[m-1 m-2]).count).to eq(2)
    end
  end

  it "says why when the listing fails" do
    stub_request(:get, "#{base}/IGUSER/media").with(query: hash_including({}))
      .to_return(status: 400, body: { error: { message: "token expired" } }.to_json, headers: json)
    allow(described_class.logger).to receive(:error)

    described_class.perform_now(account.id)

    expect(described_class.logger).to have_received(:error)
      .with(a_string_including("token expired"))
  end

  it "throttles repeated enqueues" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

    expect {
      described_class.enqueue_throttled(account)
      described_class.enqueue_throttled(account)
    }.to have_enqueued_job(described_class).exactly(:once)
  end

  it "survives an unparseable timestamp" do
    single_page([ { id: "m-1", timestamp: "2026-13-45T99:99:99" } ])

    described_class.perform_now(account.id)

    expect(InstagramConnect::MediaItem.find_by(ig_media_id: "m-1").posted_at).to be_nil
  end

  it "does nothing for a missing or inactive account" do
    account.update!(active: false)

    expect { described_class.perform_now(account.id) }
      .not_to change(InstagramConnect::MediaItem, :count)
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end

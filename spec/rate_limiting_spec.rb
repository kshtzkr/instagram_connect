require "rails_helper"

RSpec.describe "rate limiting and pagination" do
  let(:account) do
    InstagramConnect::Account.create!(ig_user_id: "IGACC", auth_path: "instagram_login", access_token: "t")
  end

  describe InstagramConnect::Usage do
    def headers(payload)
      { "x-business-use-case-usage" => payload.to_json }
    end

    it "reads the business header, which is keyed by object id" do
      usage = described_class.from_headers(
        headers("17841400008460056" => [ { "call_count" => 40, "total_cputime" => 10, "total_time" => 12 } ])
      )

      expect(usage.call_count).to eq(40)
      expect(usage.percentage).to eq(40)
    end

    it "reads the flat app header too" do
      usage = described_class.from_headers("x-app-usage" => { "call_count" => 5 }.to_json)

      expect(usage.call_count).to eq(5)
    end

    # Exhausting any one of the three throttles the app, so the worst wins.
    it "reports the worst of the three counters" do
      usage = described_class.from_headers(
        headers("1" => [ { "call_count" => 10, "total_cputime" => 91, "total_time" => 3 } ])
      )

      expect(usage.percentage).to eq(91)
      expect(usage).to be_warning
      expect(usage).not_to be_critical
    end

    it "flags a critical reading and reads Meta's recovery estimate in minutes" do
      usage = described_class.from_headers(
        headers("1" => [ { "call_count" => 97, "estimated_time_to_regain_access" => 30 } ])
      )

      expect(usage).to be_critical
      expect(usage.retry_after).to eq(1800)
    end

    # Absence is not zero usage, and must never be read as headroom.
    it "returns nil when Meta sent no usage header" do
      expect(described_class.from_headers({})).to be_nil
      expect(described_class.from_headers(nil)).to be_nil
    end

    it "returns nil rather than raising on a header it cannot parse" do
      expect(described_class.from_headers("x-app-usage" => "not json")).to be_nil
      expect(described_class.from_headers("x-app-usage" => "[]")).to be_nil
    end

    it "reports no wait when Meta gave no estimate" do
      expect(described_class.new(call_count: 99).retry_after).to be_nil
    end
  end

  describe InstagramConnect::RateLimiter do
    it "allows calls up to the bucket's limit and refuses the next one" do
      2.times { expect(described_class.acquire(account: account, bucket: :conversations)).to be_allowed }

      outcome = described_class.acquire(account: account, bucket: :conversations)
      expect(outcome).not_to be_allowed
      expect(outcome.retry_after).to be_between(1, 1)
    end

    # Fixed windows aligned to the epoch mean every process agrees on where a
    # window starts without having to coordinate.
    it "starts a fresh allowance in the next window" do
      now = Time.utc(2026, 7, 26, 12, 0, 0)
      2.times { described_class.acquire(account: account, bucket: :conversations, now: now) }

      expect(described_class.acquire(account: account, bucket: :conversations, now: now + 1))
        .to be_allowed
    end

    it "keeps buckets and accounts apart" do
      other = InstagramConnect::Account.create!(ig_user_id: "IG2", auth_path: "instagram_login", access_token: "t")
      2.times { described_class.acquire(account: account, bucket: :conversations) }

      expect(described_class.acquire(account: account, bucket: :send_text)).to be_allowed
      expect(described_class.acquire(account: other, bucket: :conversations)).to be_allowed
    end

    describe ".observe" do
      def usage(percent, regain: nil)
        InstagramConnect::Usage.new(call_count: percent, estimated_time_to_regain_access: regain)
      end

      # Meta's own numbers beat any local arithmetic — the documented formula
      # depends on impressions, which the messaging API never returns.
      it "halves the remaining allowance on a warning reading" do
        described_class.acquire(account: account, bucket: :graph)
        described_class.observe(account: account, bucket: :graph, usage: usage(85))

        budget = InstagramConnect::ApiBudget.find_by(bucket: "graph")
        expect(budget.limit_value).to eq(2400)
      end

      it "never halves below what has already been spent" do
        described_class.acquire(account: account, bucket: :conversations)
        described_class.observe(account: account, bucket: :conversations, usage: usage(85))

        budget = InstagramConnect::ApiBudget.find_by(bucket: "conversations")
        expect(budget.limit_value).to eq(2)
      end

      it "blocks the account outright on a critical reading, for Meta's stated wait" do
        described_class.acquire(account: account, bucket: :graph)
        described_class.observe(account: account, bucket: :graph, usage: usage(97, regain: 10))

        outcome = described_class.acquire(account: account, bucket: :graph)
        expect(outcome).not_to be_allowed
        expect(outcome.retry_after).to be_within(5).of(600)
      end

      it "ignores a call that came back with no usage header" do
        expect { described_class.observe(account: account, bucket: :graph, usage: nil) }
          .not_to change(InstagramConnect::ApiBudget, :count)
      end

      it "leaves the budget alone on a healthy reading" do
        described_class.acquire(account: account, bucket: :graph)

        expect { described_class.observe(account: account, bucket: :graph, usage: usage(10)) }
          .not_to(change { InstagramConnect::ApiBudget.find_by(bucket: "graph").limit_value })
      end

      it "falls back to the window when a critical reading names no wait" do
        described_class.observe(account: account, bucket: :conversations, usage: usage(99))

        expect(InstagramConnect::ApiBudget.find_by(bucket: "conversations").blocked_until).to be_present
      end
    end

    # One 429 should pause every job for that account, rather than each one
    # having to discover the block for itself.
    it "blocks a bucket when Meta names an explicit wait" do
      described_class.block!(account: account, bucket: :send_text, seconds: 120)

      outcome = described_class.acquire(account: account, bucket: :send_text)
      expect(outcome).not_to be_allowed
      expect(outcome.retry_after).to be_within(5).of(120)
    end

    it "recovers once the block has passed" do
      described_class.block!(account: account, bucket: :send_text, seconds: 60)

      expect(described_class.acquire(account: account, bucket: :send_text, now: 2.minutes.from_now))
        .to be_allowed
    end

    it "reports a bucket's own state" do
      described_class.acquire(account: account, bucket: :conversations)
      budget = InstagramConnect::ApiBudget.find_by(bucket: "conversations")

      expect(budget).not_to be_exhausted
      expect(budget).not_to be_blocked
      expect(budget.window_end).to eq(budget.window_start + 1)

      budget.update!(used: budget.limit_value)
      expect(budget).to be_exhausted
    end

    it "survives losing the create race to another process" do
      described_class.acquire(account: account, bucket: :graph)
      allow(InstagramConnect::ApiBudget).to receive(:find_or_create_by!)
        .and_raise(ActiveRecord::RecordNotUnique)

      expect(described_class.acquire(account: account, bucket: :graph)).to be_allowed
    end
  end

  describe "cursor pagination" do
    let(:client) { InstagramConnect::Client.new(access_token: "t", ig_user_id: "IGACC") }
    let(:base) { "https://graph.instagram.com/v21.0" }

    def page(records, next_cursor: nil)
      body = { data: records }
      body[:paging] = { next: "#{base}/next", cursors: { after: next_cursor } } if next_cursor
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end

    # Offsets are unsafe on a Graph collection: it shifts between calls, so an
    # offset silently skips or repeats rows.
    it "follows Meta's cursors to the end" do
      stub_request(:get, "#{base}/IGACC/media").with(query: hash_including({}))
        .to_return(page([ { "id" => "1" } ], next_cursor: "CUR1"), page([ { "id" => "2" } ]))

      result = client.collect("/IGACC/media")

      expect(result.records.map { |r| r["id"] }).to eq(%w[1 2])
      expect(WebMock).to have_requested(:get, "#{base}/IGACC/media")
        .with(query: hash_including("after" => "CUR1"))
    end

    # These collections can be unbounded and every page spends rate budget.
    it "stops at the page limit rather than walking forever" do
      stub_request(:get, "#{base}/IGACC/media").with(query: hash_including({}))
        .to_return(page([ { "id" => "x" } ], next_cursor: "CUR"))

      result = client.collect("/IGACC/media", {}, limit_pages: 3)

      expect(result.records.size).to eq(3)
      expect(WebMock).to have_requested(:get, "#{base}/IGACC/media")
        .with(query: hash_including({})).times(3)
    end

    # Meta names the wait in the error when it has one. When it does not, the
    # usage header's estimate is better than an invented backoff.
    it "falls back to the usage header for a retry wait the error did not name" do
      stub_request(:get, "#{base}/IGACC/media").with(query: hash_including({}))
        .to_return(status: 429, body: { error: { message: "slow down", code: 4 } }.to_json,
                   headers: { "Content-Type" => "application/json",
                              "x-app-usage" => { call_count: 99, estimated_time_to_regain_access: 5 }.to_json })

      result = client.collect("/IGACC/media")

      expect(result.retry_after).to eq(300)
      expect(result.usage).to be_critical
    end

    it "returns the failure instead of a partial list" do
      stub_request(:get, "#{base}/IGACC/media").with(query: hash_including({}))
        .to_return(status: 400, body: { error: { message: "nope", code: 10 } }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = client.collect("/IGACC/media")

      expect(result).to be_failure
      expect(result.error_message).to eq("nope")
    end

    it "reports a single-object response as having no records and no more pages" do
      result = InstagramConnect::Result.ok(data: { "id" => "x" })

      expect(result.records).to eq([])
      expect(result).not_to be_more
      expect(result.next_cursor).to be_nil
    end
  end
end

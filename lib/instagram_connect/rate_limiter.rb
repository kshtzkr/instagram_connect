module InstagramConnect
  # Keeps calls inside Meta's per-account ceilings.
  #
  # Meta publishes several limits at once and exhausting any of them throttles
  # the whole app for hours, so the cost of being slightly conservative is far
  # lower than the cost of being slightly wrong.
  module RateLimiter
    # Meta's documented per-account limits. The graph default is the floor of
    # the 4800 × impressions formula: impressions are not knowable from the
    # messaging API, so the floor is what is safe to assume until the usage
    # headers say otherwise.
    BUCKETS = {
      graph: { limit: 4800, window: 86_400 },
      conversations: { limit: 2, window: 1 },
      send_text: { limit: 100, window: 1 },
      send_media: { limit: 10, window: 1 },
      private_reply: { limit: 750, window: 3600 },
      publish: { limit: 50, window: 86_400 }
    }.freeze

    Outcome = Struct.new(:allowed, :retry_after, keyword_init: true) do
      def allowed? = allowed
    end

    module_function

    # Claims one call from a bucket. Returns an Outcome saying whether to
    # proceed and, if not, how long to wait — callers re-enqueue rather than
    # sleep, since a worker asleep on a rate limit is a worker not delivering
    # anything else.
    def acquire(account:, bucket:, now: Time.current)
      spec = BUCKETS.fetch(bucket.to_sym)
      row = budget_for(account, bucket, spec, now)

      return Outcome.new(allowed: false, retry_after: (row.blocked_until - now).ceil) if row.blocked?

      claimed = ApiBudget.where(id: row.id).where("used < limit_value")
                         .update_all("used = used + 1, updated_at = #{ApiBudget.connection.quote(now)}")

      if claimed == 1
        Outcome.new(allowed: true, retry_after: nil)
      else
        Outcome.new(allowed: false, retry_after: (row.window_end - now).ceil.clamp(1, spec[:window]))
      end
    end

    # Records what Meta reported after a call. Its own numbers beat any local
    # arithmetic, so a warning halves the remaining allowance and a critical
    # reading blocks the account outright until the stated recovery time.
    def observe(account:, bucket:, usage:, now: Time.current)
      return if usage.nil?

      spec = BUCKETS.fetch(bucket.to_sym)
      row = budget_for(account, bucket, spec, now)

      if usage.critical?
        row.update!(blocked_until: now + (usage.retry_after || spec[:window]))
      elsif usage.warning?
        row.update!(limit_value: [ row.limit_value / 2, row.used + 1 ].max)
      end
    end

    # Called when Meta returns an explicit retry_after: one 429 pauses every
    # job for that account, rather than each one having to discover it.
    def block!(account:, bucket:, seconds:, now: Time.current)
      spec = BUCKETS.fetch(bucket.to_sym)
      budget_for(account, bucket, spec, now).update!(blocked_until: now + seconds.to_i)
    end

    def budget_for(account, bucket, spec, now)
      start = window_start(now, spec[:window])
      ApiBudget.find_or_create_by!(
        account_id: account.id, bucket: bucket.to_s, window_start: start
      ) do |row|
        row.window_seconds = spec[:window]
        row.limit_value = spec[:limit]
      end
    rescue ActiveRecord::RecordNotUnique
      ApiBudget.find_by!(account_id: account.id, bucket: bucket.to_s, window_start: start)
    end

    # Fixed windows aligned to the epoch, so every process agrees on where a
    # window starts without having to coordinate.
    def window_start(now, seconds)
      Time.at((now.to_i / seconds) * seconds).utc
    end
  end
end

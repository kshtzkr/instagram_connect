module InstagramConnect
  class Ingest
    # One webhook event, plus the context needed to interpret it: which account
    # it belongs to, which field Meta delivered it under, and when it actually
    # happened on the wire (as opposed to when we got round to storing it).
    Envelope = Struct.new(
      :account, :object, :field, :event_type, :event, :entry_id, :occurred_at, :config,
      keyword_init: true
    ) do
      # Anything outside this is not a timestamp Meta could have sent, and
      # storing it would corrupt every ordering that reads occurred_at.
      MAX_SECONDS = 4_102_444_800 # 2100-01-01

      # Below this, a value can only be SECONDS since the epoch: the smallest
      # millisecond timestamp Meta could send (year 2001+) is ~10^12, and a
      # second-count will not reach 10^11 until the year 5138.
      MILLIS_FLOOR = 100_000_000_000

      # Meta is inconsistent on the wire: messaging webhooks stamp in
      # MILLISECONDS, comment/mention change webhooks stamp entry.time in
      # SECONDS. Dividing everything by 1000 turned every comment webhook's
      # clock into January 1970 — which read as "older than Meta's 7-day
      # reply window" and silently skipped every realtime comment automation.
      # The magnitude decides the unit; no caller has to know which field it
      # came from.
      def self.time_from(value)
        return nil if value.nil?

        number = value.to_i
        seconds = number >= MILLIS_FLOOR ? number / 1000.0 : number.to_f
        return nil unless seconds.finite? && seconds >= 0 && seconds <= MAX_SECONDS

        Time.at(seconds).utc
      end

      def dig(*keys)
        event.dig(*keys)
      end
    end
  end
end

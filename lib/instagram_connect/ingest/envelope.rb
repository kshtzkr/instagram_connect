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

      # Meta timestamps are milliseconds since the epoch. Ordering off this
      # rather than our own created_at is what stops a delayed webhook batch
      # silently reordering a conversation.
      def self.time_from(millis)
        return nil if millis.nil?

        seconds = millis.to_i / 1000.0
        return nil unless seconds.finite? && seconds >= 0 && seconds <= MAX_SECONDS

        Time.at(seconds).utc
      end

      def dig(*keys)
        event.dig(*keys)
      end
    end
  end
end

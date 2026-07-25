module InstagramConnect
  # Splits a reply that exceeds Meta's 1000-byte message ceiling into parts that
  # fit.
  #
  # Splitting rather than truncating is deliberate: a customer reading half an
  # answer is worse than reading two bubbles, and the operator who wrote it has
  # no way to know it was cut.
  module TextSplitter
    module_function

    # Returns the parts to send, in order. A message already within the limit
    # comes back as a single-element array, so callers have one code path.
    def split(text, limit: Media::Limits::TEXT_MAX_BYTES)
      text = text.to_s
      return [ text ] if text.bytesize <= limit

      parts = []
      remaining = text

      while remaining.bytesize > limit
        chunk = take(remaining, limit)
        parts << chunk.rstrip
        remaining = remaining[chunk.length..].to_s.lstrip
      end

      # Text that divides exactly on a break leaves nothing over; appending an
      # empty part would send an empty bubble.
      parts << remaining unless remaining.empty?
      parts
    end

    # The longest prefix that fits, broken at whitespace where possible so words
    # survive. Falls back to a hard character break for input with no
    # whitespace at all — a long URL, or a script that does not use spaces.
    def take(text, limit)
      candidate = +""
      last_break = nil

      text.each_char do |char|
        break if candidate.bytesize + char.bytesize > limit

        candidate << char
        last_break = candidate.length if char.match?(/\s/)
      end

      return candidate if last_break.nil?

      candidate[0, last_break]
    end
  end
end

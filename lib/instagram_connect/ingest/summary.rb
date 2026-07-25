module InstagramConnect
  class Ingest
    # What one webhook delivery produced. Behaves as a Hash so the return value
    # of Ingest.call stays compatible with hosts written against 0.2.x, which
    # read summary[:messages] and friends.
    class Summary
      COUNTERS = {
        "messages" => :messages,
        "message_echoes" => :messages,
        "messaging_postbacks" => :postbacks,
        "comments" => :comments,
        "live_comments" => :comments
      }.freeze

      attr_accessor :messages, :comments, :postbacks, :duplicates, :unhandled,
                    :failed, :callback_errors

      def initialize
        @messages = 0
        @comments = 0
        @postbacks = 0
        @duplicates = 0
        @unhandled = 0
        @failed = 0
        @callback_errors = 0
      end

      def count(field)
        counter = COUNTERS[field]
        return if counter.nil?

        public_send(:"#{counter}=", public_send(counter) + 1)
      end

      # 0.2.x reported one `skipped` number covering both "we have seen this
      # already" and "we do not parse this". They are different problems now —
      # duplicates are healthy, unhandled events are a backlog to replay — but
      # the combined figure is kept so existing hosts keep working.
      def skipped
        duplicates + unhandled
      end

      def to_h
        {
          messages: messages,
          comments: comments,
          postbacks: postbacks,
          skipped: skipped,
          duplicates: duplicates,
          unhandled: unhandled,
          failed: failed,
          callback_errors: callback_errors
        }
      end

      # Implicit conversion, not just the explicit #to_h: it is what makes a
      # Summary behave as a Hash for callers (and matchers) written against the
      # plain hash 0.2.x returned.
      alias_method :to_hash, :to_h

      def [](key)
        to_h[key.to_sym]
      end

      def ==(other)
        other.respond_to?(:to_h) ? to_h == other.to_h : super
      end

      def each(&block)
        to_h.each(&block)
      end
      include Enumerable
    end
  end
end

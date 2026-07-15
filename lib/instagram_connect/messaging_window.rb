module InstagramConnect
  # Encodes Meta's outbound messaging window. After a user's last inbound
  # message a business may send standard replies for 24h; the HUMAN_AGENT tag
  # extends that to 7 days (human replies only). Beyond that, nothing may be
  # sent until the user messages again.
  class MessagingWindow
    STANDARD_SECONDS = 24 * 60 * 60
    HUMAN_AGENT_SECONDS = 7 * 24 * 60 * 60

    def initialize(last_inbound_at:, now: Time.now)
      @last_inbound_at = last_inbound_at
      @now = now
    end

    def state
      return :closed if @last_inbound_at.nil?

      elapsed = @now - @last_inbound_at
      return :standard if elapsed <= STANDARD_SECONDS
      return :human_agent if elapsed <= HUMAN_AGENT_SECONDS

      :closed
    end

    def open?
      state != :closed
    end

    def standard?
      state == :standard
    end

    # The message tag to send with, or :blocked when no send is permitted.
    def send_tag
      case state
      when :standard then nil
      when :human_agent then "HUMAN_AGENT"
      else :blocked
      end
    end
  end
end

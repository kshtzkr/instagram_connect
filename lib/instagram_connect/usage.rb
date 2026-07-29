require "json"

# blank?/present? on plain objects — this file must not depend on which
# spec or host loaded ActiveSupport core extensions first.
require "active_support/core_ext/object/blank"

module InstagramConnect
  # Meta's own account of how much of the rate budget a call just consumed,
  # parsed from the response headers.
  #
  # This is worth having because the documented formula — 4800 calls per 24
  # hours multiplied by the account's impressions — depends on a number the
  # messaging API never returns. Any budget computed locally is a guess. These
  # headers are Meta telling you the answer directly, so they are treated as
  # ground truth and the arithmetic only as a fallback.
  class Usage
    HEADERS = %w[x-business-use-case-usage x-app-usage].freeze

    # Back off well before the wall: at 100% Meta stops answering, and the
    # penalty is measured in hours.
    WARN_AT = 80
    CRITICAL_AT = 95

    attr_reader :call_count, :total_cputime, :total_time, :estimated_time_to_regain_access

    def initialize(call_count: 0, total_cputime: 0, total_time: 0, estimated_time_to_regain_access: nil)
      @call_count = call_count.to_i
      @total_cputime = total_cputime.to_i
      @total_time = total_time.to_i
      @estimated_time_to_regain_access = estimated_time_to_regain_access
    end

    # Returns nil when Meta sent no usage headers, which is normal for some
    # endpoints — absence is not zero usage and must not be read as headroom.
    def self.from_headers(headers)
      raw = HEADERS.filter_map { |name| headers&.[](name) }.first
      return nil if raw.blank?

      payload = JSON.parse(raw)
      # The business header is keyed by object id and holds an array; the app
      # header is a flat hash.
      metrics = payload.is_a?(Hash) && payload.values.first.is_a?(Array) ? payload.values.first.first : payload
      return nil unless metrics.is_a?(Hash)

      new(
        call_count: metrics["call_count"],
        total_cputime: metrics["total_cputime"],
        total_time: metrics["total_time"],
        estimated_time_to_regain_access: metrics["estimated_time_to_regain_access"]
      )
    rescue JSON::ParserError
      nil
    end

    # The worst of the three, since exhausting any one of them throttles the app.
    def percentage
      [ call_count, total_cputime, total_time ].max
    end

    def warning?
      percentage >= WARN_AT
    end

    def critical?
      percentage >= CRITICAL_AT
    end

    def retry_after
      estimated_time_to_regain_access.to_i * 60 if estimated_time_to_regain_access.to_i.positive?
    end
  end
end

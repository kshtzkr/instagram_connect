module InstagramConnect
  # Value object returned by every Client call. Client methods never raise for
  # API-level failures — callers branch on +success?+ and read +error_code+ /
  # +error_message+. Transport/programming errors still raise.
  class Result
    attr_reader :success, :id, :error_code, :error_message, :retry_after, :data, :usage

    def initialize(success:, id: nil, error_code: nil, error_message: nil, retry_after: nil,
                   data: {}, usage: nil)
      @success = success
      @id = id
      @error_code = error_code
      @error_message = error_message
      @retry_after = retry_after
      @data = data || {}
      @usage = usage
    end

    def success?
      success
    end

    def failure?
      !success?
    end

    # Meta's cursor for the next page, or nil when this is the last one. Reading
    # `paging.next` rather than incrementing an offset is the only correct way
    # through a Graph collection — results shift under you between calls.
    def next_cursor
      data.dig("paging", "cursors", "after").presence if more?
    end

    def more?
      data.is_a?(Hash) && data.dig("paging", "next").present?
    end

    # The rows of a collection response, or [] for a single-object one.
    def records
      list = data["data"]
      list.is_a?(Array) ? list : []
    end

    # Convenience builders so call sites read cleanly.
    def self.ok(id: nil, data: {}, usage: nil)
      new(success: true, id: id, data: data, usage: usage)
    end

    def self.error(message, error_code: nil, retry_after: nil, data: {}, usage: nil)
      new(success: false, error_message: message, error_code: error_code,
          retry_after: retry_after, data: data, usage: usage)
    end
  end
end

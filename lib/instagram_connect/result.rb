module InstagramConnect
  # Value object returned by every Client call. Client methods never raise for
  # API-level failures — callers branch on +success?+ and read +error_code+ /
  # +error_message+. Transport/programming errors still raise.
  class Result
    attr_reader :success, :id, :error_code, :error_message, :retry_after, :data

    def initialize(success:, id: nil, error_code: nil, error_message: nil, retry_after: nil, data: {})
      @success = success
      @id = id
      @error_code = error_code
      @error_message = error_message
      @retry_after = retry_after
      @data = data || {}
    end

    def success?
      success
    end

    def failure?
      !success?
    end

    # Convenience builders so call sites read cleanly.
    def self.ok(id: nil, data: {})
      new(success: true, id: id, data: data)
    end

    def self.error(message, error_code: nil, retry_after: nil, data: {})
      new(success: false, error_message: message, error_code: error_code, retry_after: retry_after, data: data)
    end
  end
end

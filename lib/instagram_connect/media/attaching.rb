require "marcel"
require "stringio"

module InstagramConnect
  module Media
    # Turns fetched bytes into a stored file, or into an honest reason why not.
    #
    # The rule that matters here: when the declared Content-Type and the actual
    # magic bytes disagree, the magic bytes win. A Content-Type header is
    # metadata anyone can set; the first few bytes of the file are what the file
    # actually is. Trusting the header is how a host ends up serving an HTML
    # document from an <img> tag.
    module Attaching
      Result = Struct.new(:ok, :mime, :size, :error, keyword_init: true) do
        def ok? = ok
      end

      module_function

      def evaluate(body:, declared_mime:, filename: nil, config: InstagramConnect.configuration)
        bytes = body.to_s
        return failure("empty") if bytes.empty?

        mime = sniff(bytes, filename: filename, declared: declared_mime)
        return failure("type_not_allowed:#{mime}") unless allowed?(mime, config)
        return failure("too_large:#{bytes.bytesize}") unless within_size?(mime, bytes.bytesize, config)

        Result.new(ok: true, mime: mime, size: bytes.bytesize)
      end

      def sniff(bytes, filename: nil, declared: nil)
        sniffed = ::Marcel::MimeType.for(StringIO.new(bytes), name: filename)
        # Marcel falls back to this when it recognises nothing, in which case the
        # declared type is the only information available and is better than
        # nothing.
        return declared.to_s.split(";").first.to_s.strip if sniffed == "application/octet-stream" && declared.present?

        sniffed
      end

      def allowed?(mime, config)
        allowed = config.allowed_media_types
        allowed.blank? || allowed.include?(mime)
      end

      # Both Meta's per-type ceiling and the host's own cap have to hold. The
      # host's exists so an adopter can be stricter than Meta, never looser.
      def within_size?(mime, bytes, config)
        Limits.within_size?(mime, bytes) && bytes <= config.media_max_bytes.to_i
      end

      def failure(reason)
        Result.new(ok: false, error: reason)
      end
    end
  end
end

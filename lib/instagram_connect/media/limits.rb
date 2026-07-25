module InstagramConnect
  module Media
    # Meta's ceilings, in one place, read by the composer, the send path and the
    # client so the numbers cannot drift apart.
    module Limits
      IMAGE_MAX_BYTES = 8 * 1024 * 1024
      AUDIO_VIDEO_MAX_BYTES = 25 * 1024 * 1024
      ATTACHMENTS_MAX = 10

      # BYTES, not characters. An emoji-heavy 400-character reply is over the
      # limit and Meta rejects the whole send, so anything measuring this with
      # String#length is measuring the wrong thing.
      TEXT_MAX_BYTES = 1000

      IMAGE_TYPES = %w[image/jpeg image/png image/gif].freeze
      AUDIO_TYPES = %w[audio/aac audio/mp4 audio/mpeg audio/ogg audio/wav].freeze
      VIDEO_TYPES = %w[video/mp4 video/ogg video/avi video/quicktime video/webm].freeze

      module_function

      # The ceiling that applies to a given MIME type. Images get a tighter one
      # than audio and video, and an unknown type is held to the tighter of the
      # two rather than waved through.
      def max_bytes_for(mime)
        image?(mime) ? IMAGE_MAX_BYTES : AUDIO_VIDEO_MAX_BYTES
      end

      def image?(mime)
        IMAGE_TYPES.include?(mime.to_s)
      end

      def within_size?(mime, bytes)
        bytes.to_i.positive? && bytes.to_i <= max_bytes_for(mime)
      end

      # Only images can be batched; Meta accepts one audio or video per message.
      def attachments_within_limit?(count)
        count.to_i <= ATTACHMENTS_MAX
      end

      def text_within_limit?(text)
        text.to_s.bytesize <= TEXT_MAX_BYTES
      end
    end
  end
end

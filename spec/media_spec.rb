require "rails_helper"

RSpec.describe "media" do
  describe InstagramConnect::Media::Limits do
    it "holds images to Meta's tighter ceiling and audio/video to the looser one" do
      expect(described_class.max_bytes_for("image/jpeg")).to eq(8 * 1024 * 1024)
      expect(described_class.max_bytes_for("video/mp4")).to eq(25 * 1024 * 1024)
    end

    # An unknown type getting the image ceiling would be the wrong-way error:
    # it is the tighter of the two, so nothing oversized slips through.
    it "gives an unrecognised type the audio/video ceiling" do
      expect(described_class.max_bytes_for("application/octet-stream")).to eq(25 * 1024 * 1024)
      expect(described_class).not_to be_image("application/octet-stream")
    end

    it "rejects an empty file as well as an oversized one" do
      expect(described_class.within_size?("image/jpeg", 0)).to be(false)
      expect(described_class.within_size?("image/jpeg", 9 * 1024 * 1024)).to be(false)
      expect(described_class.within_size?("image/jpeg", 1024)).to be(true)
    end

    it "caps a message at ten attachments" do
      expect(described_class.attachments_within_limit?(10)).to be(true)
      expect(described_class.attachments_within_limit?(11)).to be(false)
    end

    # The limit is bytes, not characters. Measuring with String#length lets an
    # emoji-heavy reply through and Meta rejects the whole send.
    it "measures the text ceiling in bytes" do
      emoji = "🎉" * 300 # 1200 bytes, 300 characters

      expect(emoji.length).to be < described_class::TEXT_MAX_BYTES
      expect(described_class.text_within_limit?(emoji)).to be(false)
      expect(described_class.text_within_limit?("a" * 1000)).to be(true)
    end
  end

  describe InstagramConnect::TextSplitter do
    it "leaves a message within the limit alone" do
      expect(described_class.split("hello")).to eq([ "hello" ])
    end

    it "splits on whitespace so words survive" do
      parts = described_class.split("#{'word ' * 300}end")

      expect(parts.size).to be > 1
      expect(parts).to all(satisfy { |part| part.bytesize <= 1000 })
      expect(parts.join(" ")).to include("end")
      expect(parts.first).not_to end_with(" ")
    end

    # Splitting rather than truncating is the point: a customer reading half an
    # answer is worse than reading two bubbles, and the operator cannot tell.
    it "keeps every character rather than truncating" do
      text = (1..400).map { |n| "n#{n}" }.join(" ")

      expect(described_class.split(text).join(" ")).to eq(text)
    end

    it "breaks a long unbroken run of characters rather than giving up" do
      parts = described_class.split("x" * 2500)

      expect(parts.size).to eq(3)
      expect(parts.join).to eq("x" * 2500)
    end

    it "emits no trailing empty part when the text divides exactly" do
      parts = described_class.split("#{'a' * 1000} ")

      expect(parts).to eq([ "a" * 1000 ])
    end

    it "never emits a part over the limit for multi-byte text" do
      parts = described_class.split("🎉" * 900)

      expect(parts).to all(satisfy { |part| part.bytesize <= 1000 })
      expect(parts.join).to eq("🎉" * 900)
    end
  end

  describe InstagramConnect::Media::Attaching do
    let(:jpeg) { "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00#{'padding' * 20}".b }

    it "accepts a file whose bytes match an allowed type" do
      result = described_class.evaluate(body: jpeg, declared_mime: "image/jpeg")

      expect(result).to be_ok
      expect(result.mime).to eq("image/jpeg")
      expect(result.size).to eq(jpeg.bytesize)
    end

    # A Content-Type header is metadata anyone can set; the magic bytes are what
    # the file actually is. Trusting the header is how a host ends up serving an
    # HTML document out of an <img> tag.
    it "believes the magic bytes over a lying Content-Type" do
      result = described_class.evaluate(body: "<html>gotcha</html>", declared_mime: "image/jpeg")

      expect(result).not_to be_ok
      expect(result.error).to start_with("type_not_allowed")
    end

    it "falls back to the declared type only when the bytes say nothing" do
      mime = described_class.sniff("\x00\x01\x02\x03".b, declared: "audio/aac")

      expect(mime).to eq("audio/aac")
    end

    it "keeps the sniffed type when the bytes are recognisable" do
      expect(described_class.sniff(jpeg, declared: "audio/aac")).to eq("image/jpeg")
    end

    it "rejects an empty body before doing anything else" do
      expect(described_class.evaluate(body: "", declared_mime: "image/jpeg").error).to eq("empty")
    end

    it "enforces the host's cap as well as Meta's" do
      InstagramConnect.configuration.media_max_bytes = 10

      result = described_class.evaluate(body: jpeg, declared_mime: "image/jpeg")

      expect(result).not_to be_ok
      expect(result.error).to start_with("too_large")
    end

    it "allows any type when the host has cleared its allowlist" do
      InstagramConnect.configuration.allowed_media_types = []

      expect(described_class.evaluate(body: "<html>x</html>", declared_mime: "text/html")).to be_ok
    end
  end
end

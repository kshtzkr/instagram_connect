module InstagramConnect
  # Parses a verified Meta webhook payload and persists it into the engine's
  # chat models, deduping on Meta's message id. After persistence it fires the
  # configured host handlers (on_message / on_comment / on_postback) so the host
  # can layer extras (notifications, AI replies) on top.
  #
  # Returns a summary hash of what was processed.
  class Ingest
    def self.call(payload:, config: InstagramConnect.configuration)
      new(config).call(payload)
    end

    def initialize(config)
      @config = config
    end

    def call(payload)
      summary = { messages: 0, comments: 0, postbacks: 0, skipped: 0 }
      Array(payload && payload["entry"]).each do |entry|
        account = account_for(entry)
        if account.nil?
          summary[:skipped] += 1
          next
        end
        Array(entry["messaging"]).each { |event| ingest_messaging(account, event, summary) }
        Array(entry["changes"]).each { |change| ingest_change(account, change, summary) }
      end
      summary
    end

    private

    attr_reader :config

    def account_for(entry)
      id = entry["id"].to_s
      Account.find_by(ig_user_id: id) || Account.find_by(page_id: id)
    end

    def ingest_messaging(account, event, summary)
      if event["message"]
        ingest_message(account, event, summary)
      elsif event["postback"]
        invoke(config.on_postback, build_postback(account, event))
        summary[:postbacks] += 1
      else
        summary[:skipped] += 1
      end
    end

    def ingest_message(account, event, summary)
      msg = event["message"]
      mid = msg["mid"].to_s
      if mid.empty? || !InboundMessage.claim(ig_message_id: mid, account_id: account.id)
        summary[:skipped] += 1
        return
      end

      echo = msg["is_echo"] ? true : false
      igsid = (echo ? event.dig("recipient", "id") : event.dig("sender", "id")).to_s
      conversation = Conversation.locate(account: account, igsid: igsid)
      message = Message.create!(
        conversation: conversation,
        direction: echo ? "outbound" : "inbound",
        status: echo ? "sent" : "received",
        source: echo ? "operator_app" : "inbound",
        kind: "dm",
        body: msg["text"],
        ig_message_id: mid,
        media_status: media?(msg) ? "pending" : "none"
      )
      conversation.register_message(message)
      invoke(config.on_message, message) unless echo
      summary[:messages] += 1
    end

    def ingest_change(account, change, summary)
      unless change["field"] == "comments"
        summary[:skipped] += 1
        return
      end
      value = change["value"] || {}
      comment = Comment.record(
        account: account,
        comment_id: value["id"].to_s,
        media_id: value.dig("media", "id"),
        text: value["text"],
        from_username: value.dig("from", "username"),
        parent_id: value["parent_id"]
      )
      invoke(config.on_comment, comment)
      summary[:comments] += 1
    end

    def media?(msg)
      Array(msg["attachments"]).any?
    end

    def build_postback(account, event)
      {
        account_id: account.id,
        sender_id: event.dig("sender", "id"),
        payload: event.dig("postback", "payload"),
        title: event.dig("postback", "title")
      }
    end

    def invoke(handler, arg)
      handler.call(arg) if handler.respond_to?(:call)
    end
  end
end

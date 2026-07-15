module InstagramConnect
  # Sends one pending outbound Message via the Graph API, exactly once. Claims
  # the row (pending -> sending) with an atomic UPDATE so a duplicate enqueue
  # can't double-send, then enforces Meta's messaging window — auto-applying the
  # HUMAN_AGENT tag once the standard 24h window has passed.
  class SendMessageJob < ApplicationJob
    queue_as :default

    def perform(message_id)
      claimed = Message.where(id: message_id, status: "pending")
                       .update_all(status: "sending", updated_at: Time.current)
      return unless claimed == 1

      message = Message.find(message_id)
      tag = MessagingWindow.new(last_inbound_at: message.conversation.last_inbound_at).send_tag

      if tag == :blocked
        return fail_message(message, "outside_messaging_window",
                            "The reply window has closed; the customer must message again.")
      end

      deliver(message, tag)
    end

    private

    def deliver(message, tag)
      conversation = message.conversation
      account = conversation.account
      client = Client.new(access_token: account.access_token, ig_user_id: account.ig_user_id)
      result = client.send_text(recipient_id: conversation.igsid, text: message.body.to_s, tag: tag)

      if result.success?
        message.update!(status: "sent", ig_message_id: result.id, message_tag: tag)
      else
        fail_message(message, result.error_code&.to_s, result.error_message)
      end
    end

    def fail_message(message, reason, error)
      message.update!(status: "failed", failure_reason: reason, error_message: error)
    end
  end
end

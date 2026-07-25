module InstagramConnect
  # Sends one pending outbound Message via the Graph API, exactly once.
  #
  # The claim is an atomic UPDATE from pending to sending, so a duplicate
  # enqueue cannot double-send. Everything after it keeps an at-most-once bias:
  # on any doubt the message is marked failed for an operator to retry
  # deliberately, never resent automatically. A duplicate message reaching a
  # customer is worse than a visible failure.
  class SendMessageJob < ApplicationJob
    queue_as :default

    def perform(message_id)
      claimed = Message.where(id: message_id, status: "pending")
                       .update_all(status: "sending", updated_at: Time.current)
      return unless claimed == 1

      message = Message.find(message_id)
      # The claim was callback-free, so a host rendering this thread live needs
      # telling before the send starts rather than after it finishes.
      message.broadcast_refresh

      conversation = message.conversation

      # Meta rejects a send on a thread another app owns, and the error it
      # returns says nothing useful about why. Refusing here names the reason.
      if conversation.controlled_elsewhere?
        return fail_message(message, "thread_controlled_elsewhere",
                            "Another app currently has control of this conversation.")
      end

      tag = MessagingWindow.new(last_inbound_at: conversation.last_inbound_at).send_tag
      if tag == :blocked
        return fail_message(message, "outside_messaging_window",
                            "The reply window has closed; the customer must message again.")
      end

      deliver(message, conversation, tag)
    end

    private

    def deliver(message, conversation, tag)
      client = client_for(conversation.account)
      parts = TextSplitter.split(message.body.to_s)

      # Resume rather than restart. A worker killed mid-fan-out has already
      # delivered the earlier parts, and re-sending them repeats text the
      # customer can already see.
      parts.drop(message.delivered_parts_count).each do |part|
        result = client.send_text(recipient_id: conversation.igsid, text: part, tag: tag)
        return fail_message(message, result.error_code&.to_s, result.error_message) unless result.success?

        message.update!(
          delivered_parts_count: message.delivered_parts_count + 1,
          # Meta returns an id per send. The first is the message's identity and
          # the one its echo will carry back.
          ig_message_id: message.ig_message_id.presence || result.id
        )
      end

      message.update!(status: "sent", message_tag: tag)
      message.broadcast_refresh
      message
    end

    def client_for(account)
      Client.new(access_token: account.access_token, ig_user_id: account.ig_user_id)
    end

    def fail_message(message, reason, error)
      message.update!(status: "failed", failure_reason: reason, error_message: error)
      message.broadcast_refresh
      nil
    end
  end
end

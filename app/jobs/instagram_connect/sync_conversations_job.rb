module InstagramConnect
  # Pulls the threads that already exist on the account.
  #
  # Webhooks only ever announce NEW activity, so a freshly connected account
  # shows an empty inbox until somebody happens to message in — even though the
  # operator has years of conversations sitting in Instagram. This fetches what
  # Meta will give us: every thread, and the 20 most recent messages in each,
  # which is the entire history the API exposes to any app.
  #
  # Safe to re-run. Threads are located by igsid and messages are deduped on
  # ig_message_id, so a second pass updates rather than duplicates.
  class SyncConversationsJob < ApplicationJob
    queue_as :default

    def perform(account_id)
      account = Account.find_by(id: account_id)
      return if account.nil? || !account.active?

      threads = account.client.list_conversations
      return unless threads.success?

      Array(threads.data["data"]).each { |thread| sync_thread(account, thread["id"]) }
    end

    private

    def sync_thread(account, conversation_id)
      result = account.client.conversation_messages(conversation_id: conversation_id)
      return unless result.success?

      messages = Array(result.data.dig("messages", "data"))
      # A thread with no readable messages tells us nothing and would show as an
      # empty row in the inbox, so it is skipped rather than created.
      return if messages.empty?

      conversation = Conversation.locate(account: account, igsid: counterpart(messages, account))
      messages.reverse_each { |message| import(conversation, account, message) }
    end

    # Meta reports both ends of every message; the thread belongs to whichever
    # participant is not us.
    def counterpart(messages, account)
      messages.each do |message|
        [ message.dig("from", "id"), *Array(message.dig("to", "data")).map { |t| t["id"] } ]
          .compact.each { |id| return id.to_s if id.to_s != account.ig_user_id.to_s }
      end
      account.ig_user_id.to_s
    end

    def import(conversation, account, payload)
      mid = payload["id"].to_s
      return if mid.blank?

      message = Message.find_or_initialize_by(conversation_id: conversation.id, ig_message_id: mid)
      return unless message.new_record?

      outbound = payload.dig("from", "id").to_s == account.ig_user_id.to_s
      message.assign_attributes(
        direction: outbound ? "outbound" : "inbound",
        # Historical rows: an outbound message we are reading back has already
        # been delivered, and an inbound one has already arrived.
        status: outbound ? "sent" : "received",
        body: payload["message"],
        source: "sync",
        sent_at: parse_time(payload["created_time"])
      )
      message.account_id = account.id
      message.save!
      conversation.register_message(message)
    rescue ActiveRecord::RecordNotUnique
      # Raced a webhook for the same message. The webhook's copy is the one that
      # matters; ours would have been identical.
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

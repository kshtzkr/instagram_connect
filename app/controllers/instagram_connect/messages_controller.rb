module InstagramConnect
  # Composes an outbound reply in a thread and hands it to the send job.
  class MessagesController < ApplicationController
    def create
      conversation = Conversation.find(params[:conversation_id])

      if params[:body].to_s.strip.empty?
        return redirect_to conversation_path(conversation), alert: "Message can't be blank."
      end

      message = conversation.messages.create!(
        direction: "outbound", status: "pending", kind: "dm", source: "manual",
        body: params[:body], sent_by_id: instagram_connect_user_id
      )
      SendMessageJob.perform_later(message.id)
      redirect_to conversation_path(conversation), notice: "Reply queued."
    end
  end
end

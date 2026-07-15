module InstagramConnect
  # The DM inbox: a paginated list of threads and a single thread view.
  class ConversationsController < ApplicationController
    def index
      per = InstagramConnect.configuration.default_per_page
      @page = [ params[:page].to_i, 1 ].max
      @conversations = Conversation.recent.limit(per).offset((@page - 1) * per)
    end

    def show
      @conversation = Conversation.find(params[:id])
      @messages = @conversation.messages.chronological
      @conversation.update!(unread_count: 0) if @conversation.unread_count.positive?
      @window = MessagingWindow.new(last_inbound_at: @conversation.last_inbound_at)
    end
  end
end

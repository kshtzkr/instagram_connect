module InstagramConnect
  # Moderate comments on the account's media: list, reply, hide/unhide, delete.
  # Moderation calls the Graph API synchronously (fast, operator-facing) and only
  # updates local state on success.
  class CommentsController < ApplicationController
    before_action :set_comment, only: %i[reply hide unhide destroy]

    def index
      per = InstagramConnect.configuration.default_per_page
      @page = [ params[:page].to_i, 1 ].max
      @comments = Comment.order(created_at: :desc).limit(per).offset((@page - 1) * per)
    end

    def reply
      moderate(notice: "Reply posted.",
               call: ->(client) { client.reply_comment(comment_id: @comment.comment_id, text: params[:text].to_s) },
               on_success: -> { @comment.update!(replied_at: Time.current) })
    end

    def hide
      moderate(notice: "Comment hidden.",
               call: ->(client) { client.hide_comment(comment_id: @comment.comment_id, hidden: true) },
               on_success: -> { @comment.update!(hidden_at: Time.current) })
    end

    def unhide
      moderate(notice: "Comment unhidden.",
               call: ->(client) { client.hide_comment(comment_id: @comment.comment_id, hidden: false) },
               on_success: -> { @comment.update!(hidden_at: nil) })
    end

    def destroy
      moderate(notice: "Comment deleted.",
               call: ->(client) { client.delete_comment(comment_id: @comment.comment_id) },
               on_success: -> { @comment.destroy! })
    end

    private

    def set_comment
      @comment = Comment.find(params[:id])
    end

    def moderate(notice:, call:, on_success:)
      result = call.call(client_for(@comment))
      if result.success?
        on_success.call
        redirect_to comments_path, notice: notice
      else
        redirect_to comments_path, alert: result.error_message
      end
    end

    def client_for(comment)
      account = comment.account
      Client.new(access_token: account.access_token, ig_user_id: account.ig_user_id)
    end
  end
end

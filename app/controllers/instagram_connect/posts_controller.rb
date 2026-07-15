module InstagramConnect
  # Publishing: list the account's own media and publish a new image post
  # (container -> publish). Reels/video/carousel are a documented follow-on.
  class PostsController < ApplicationController
    before_action :require_account

    def index
      client = client_for(@account)
      @media = Array(client.list_media.data["data"])
      @quota_usage = client.publishing_limit.data.dig("data", 0, "quota_usage")
    end

    def new
    end

    def create
      client = client_for(@account)
      container = client.create_media_container(image_url: params[:image_url], caption: params[:caption])
      return redirect_to new_post_path, alert: container.error_message if container.failure?

      published = client.publish_media(creation_id: container.id)
      if published.success?
        redirect_to posts_path, notice: "Published to Instagram."
      else
        redirect_to new_post_path, alert: published.error_message
      end
    end

    private

    def require_account
      @account = Account.active.first
      redirect_to conversations_path, alert: "Connect an Instagram account first." if @account.nil?
    end

    def client_for(account)
      Client.new(access_token: account.access_token, ig_user_id: account.ig_user_id)
    end
  end
end

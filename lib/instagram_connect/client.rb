require "httparty"

module InstagramConnect
  # Thin wrapper over the Meta Graph API, bound to one account's access token.
  # Every call returns a Result — API-level failures never raise, callers branch
  # on success?. The Graph host + version come from the configured auth strategy.
  class Client
    TIMEOUT = 30

    def initialize(access_token:, config: InstagramConnect.configuration, ig_user_id: nil)
      @access_token = access_token
      @config = config
      @ig_user_id = ig_user_id
      @strategy = Auth.for(config)
    end

    # --- Direct messages -------------------------------------------------

    def send_text(recipient_id:, text:, tag: nil)
      send_message(recipient: { id: recipient_id }, message: { text: text }, tag: tag)
    end

    def send_media(recipient_id:, url:, type: "image", tag: nil)
      attachment = { type: type, payload: { url: url } }
      send_message(recipient: { id: recipient_id }, message: { attachment: attachment }, tag: tag)
    end

    def send_reaction(recipient_id:, message_id:, reaction: "love")
      post("/me/messages", {
        recipient: { id: recipient_id },
        sender_action: "react",
        payload: { message_id: message_id, reaction: reaction }
      })
    end

    # One-time private reply to a comment (comment -> DM), valid 7 days.
    def private_reply(comment_id:, text:)
      post("/me/messages", { recipient: { comment_id: comment_id }, message: { text: text } })
    end

    # --- Comments --------------------------------------------------------

    def reply_comment(comment_id:, text:)
      post("/#{comment_id}/replies", { message: text })
    end

    def hide_comment(comment_id:, hidden: true)
      post("/#{comment_id}", { hide: hidden })
    end

    def delete_comment(comment_id:)
      delete("/#{comment_id}")
    end

    def list_comments(media_id:, limit: 50)
      get("/#{media_id}/comments", { fields: "id,text,username,timestamp,parent_id", limit: limit })
    end

    # --- Publishing ------------------------------------------------------

    def create_media_container(ig_user_id: @ig_user_id, **params)
      post("/#{require_ig_user_id(ig_user_id)}/media", params)
    end

    def publish_media(creation_id:, ig_user_id: @ig_user_id)
      post("/#{require_ig_user_id(ig_user_id)}/media_publish", { creation_id: creation_id })
    end

    def container_status(container_id:)
      get("/#{container_id}", { fields: "status_code,status" })
    end

    def publishing_limit(ig_user_id: @ig_user_id)
      get("/#{require_ig_user_id(ig_user_id)}/content_publishing_limit", { fields: "quota_usage,config" })
    end

    # --- Reads -----------------------------------------------------------

    def list_media(ig_user_id: @ig_user_id, limit: 25)
      get("/#{require_ig_user_id(ig_user_id)}/media",
          { fields: "id,caption,media_type,media_url,permalink,timestamp", limit: limit })
    end

    def media_insights(media_id:, metrics: %w[reach likes comments])
      get("/#{media_id}/insights", { metric: Array(metrics).join(",") })
    end

    def profile(igsid:, fields: %w[name username profile_pic])
      get("/#{igsid}", { fields: Array(fields).join(",") })
    end

    # FB-Login only: the Pages this user administers, with their linked IG
    # business account — used to resolve the account identity after OAuth.
    def list_pages
      get("/me/accounts", { fields: "id,name,access_token,instagram_business_account" })
    end

    def fetch_media_binary(url:)
      response = HTTParty.get(url, headers: bearer, timeout: TIMEOUT, follow_redirects: true)
      unless response.success?
        return Result.error("media fetch failed: HTTP #{response.code}", error_code: response.code)
      end
      body = response.body.to_s
      Result.ok(data: { body: body, mime: response.headers["content-type"], size: body.bytesize })
    end

    private

    attr_reader :access_token, :config, :strategy

    def send_message(recipient:, message:, tag: nil)
      body = { recipient: recipient, message: message }
      if tag
        body[:messaging_type] = "MESSAGE_TAG"
        body[:tag] = tag
      end
      post("/me/messages", body)
    end

    def require_ig_user_id(value)
      value || raise(ConfigurationError, "ig_user_id is required for this call")
    end

    def get(path, query = {})
      parse(HTTParty.get(url(path), headers: bearer, query: query, timeout: TIMEOUT))
    end

    def post(path, body = {})
      parse(HTTParty.post(url(path),
                          headers: bearer.merge("Content-Type" => "application/json"),
                          body: body.to_json, timeout: TIMEOUT))
    end

    def delete(path)
      parse(HTTParty.delete(url(path), headers: bearer, timeout: TIMEOUT))
    end

    def url(path)
      "#{strategy.graph_host}/#{config.graph_version}#{path}"
    end

    def bearer
      { "Authorization" => "Bearer #{access_token}" }
    end

    def parse(response)
      data = response.parsed_response
      data = {} unless data.is_a?(Hash)
      if response.success?
        Result.ok(id: data["message_id"] || data["id"], data: data)
      else
        err = data["error"].is_a?(Hash) ? data["error"] : {}
        Result.error(err["message"] || "HTTP #{response.code}",
                     error_code: err["code"],
                     retry_after: err.dig("error_data", "retry_after"),
                     data: data)
      end
    end
  end
end

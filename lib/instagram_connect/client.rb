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

    # Typing indicators and read receipts. Meta is explicit that a sender action
    # request must carry ONLY the recipient and the action — bundling it with a
    # message silently drops one of the two.
    def send_sender_action(recipient_id:, action:)
      post("/me/messages", { recipient: { id: recipient_id }, sender_action: action })
    end

    def send_quick_replies(recipient_id:, text:, replies:, tag: nil)
      quick_replies = Array(replies).map do |reply|
        { content_type: "text", title: reply[:title].to_s[0, 20], payload: reply[:payload].to_s }
      end
      send_message(recipient: { id: recipient_id },
                   message: { text: text, quick_replies: quick_replies }, tag: tag)
    end

    def send_attachment(recipient_id:, attachment_id:, tag: nil)
      send_message(recipient: { id: recipient_id },
                   message: { attachment: { payload: { attachment_id: attachment_id } } }, tag: tag)
    end

    # Uploads bytes to Meta and returns a reusable attachment id.
    #
    # Preferred over handing Meta a signed URL to the host's storage: a signed
    # URL is a bearer capability for a customer's file, sitting on the public
    # internet for as long as its TTL, fetched from an address we do not
    # control. This moves the bytes over an authenticated POST instead, and the
    # returned id can be reused rather than re-uploading the same file.
    # +file+ must be a File or Tempfile — HTTParty builds the multipart body
    # from objects that expose a path, which is also what ActiveStorage's
    # blob.open yields.
    def upload_attachment(file:, type: "image")
      body = {
        platform: "instagram",
        message: { attachment: { type: type, payload: { is_reusable: true } } }.to_json,
        filedata: file
      }
      post_multipart("/me/message_attachments", body)
    end

    # Ice breakers and the persistent menu both live on the messenger profile.
    def set_messenger_profile(**fields)
      post("/me/messenger_profile", fields.merge(platform: "instagram"))
    end

    def messenger_profile(fields:)
      get("/me/messenger_profile", { fields: Array(fields).join(","), platform: "instagram" })
    end

    def delete_messenger_profile(fields:)
      parse(HTTParty.delete(url("/me/messenger_profile"),
                            headers: bearer.merge("Content-Type" => "application/json"),
                            body: { fields: Array(fields), platform: "instagram" }.to_json,
                            timeout: TIMEOUT))
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

    # The connected account's own profile. A different call from #profile,
    # which looks up the person on the other end of a thread.
    def account_profile(ig_user_id: @ig_user_id, fields: %w[username name profile_picture_url
                                                            followers_count media_count])
      get("/#{require_ig_user_id(ig_user_id)}", { fields: Array(fields).join(",") })
    end

    def profile(igsid:, fields: %w[name username profile_pic])
      get("/#{igsid}", { fields: Array(fields).join(",") })
    end

    # FB-Login only: the Pages this user administers, with their linked IG
    # business account — used to resolve the account identity after OAuth.
    def list_pages
      get("/me/accounts", { fields: "id,name,access_token,instagram_business_account" })
    end

    # Walks a Graph collection to the end, following Meta's own cursors.
    #
    # Offsets are not safe here: a collection can shift between calls, so an
    # offset silently skips or repeats rows. +limit_pages+ exists because these
    # collections can be unbounded and every page spends rate budget.
    def each_page(path, query = {}, limit_pages: 25)
      cursor = nil
      pages = 0

      while pages < limit_pages
        page_query = cursor ? query.merge(after: cursor) : query
        result = get(path, page_query)
        return result unless result.success?

        yield result
        pages += 1
        cursor = result.next_cursor
        break if cursor.nil?
      end

      Result.ok(data: { "pages" => pages })
    end

    # Every record across every page, for callers that just want the list.
    def collect(path, query = {}, limit_pages: 25)
      records = []
      result = each_page(path, query, limit_pages: limit_pages) { |page| records.concat(page.records) }
      return result if result.failure?

      Result.ok(data: { "data" => records })
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

    # multipart/form-data rather than JSON. The Attachment Upload API takes raw
    # bytes, which a JSON body cannot carry.
    def post_multipart(path, body)
      parse(HTTParty.post(url(path), headers: bearer, body: body,
                          multipart: true, timeout: TIMEOUT))
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
      usage = Usage.from_headers(response.headers)
      if response.success?
        Result.ok(id: data["message_id"] || data["id"], data: data, usage: usage)
      else
        err = data["error"].is_a?(Hash) ? data["error"] : {}
        Result.error(err["message"] || "HTTP #{response.code}",
                     error_code: err["code"],
                     # Meta names the wait in the error when it has one; when it
                     # does not, the usage header's estimate is the next best
                     # thing and is better than an invented backoff.
                     retry_after: err.dig("error_data", "retry_after") || usage&.retry_after,
                     data: data,
                     usage: usage)
      end
    end
  end
end

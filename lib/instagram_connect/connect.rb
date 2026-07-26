module InstagramConnect
  # Turns an OAuth authorization code into a persisted Account. Extracted from
  # the callback controller so the flow is unit-testable without the HTTP layer.
  class Connect
    def self.call(code:, redirect_uri:, config: InstagramConnect.configuration, connected_by_id: nil)
      new(config).call(code: code, redirect_uri: redirect_uri, connected_by_id: connected_by_id)
    end

    def initialize(config)
      @config = config
      @strategy = Auth.for(config)
    end

    def call(code:, redirect_uri:, connected_by_id: nil)
      data = @strategy.exchange_code(code: code, redirect_uri: redirect_uri)
      identity = resolve_identity(data)

      account = Account.find_or_initialize_by(ig_user_id: identity[:ig_user_id])
      account.assign_attributes(
        auth_path: @config.auth_path.to_s,
        access_token: data[:access_token],
        token_expires_at: data[:expires_at],
        page_id: identity[:page_id],
        active: true
      )
      account.connected_by_id = connected_by_id unless connected_by_id.nil?
      account.save!
      # Webhooks only announce new activity, so without this the operator
      # connects and stares at an empty inbox beside an Instagram account full
      # of conversations.
      SyncConversationsJob.perform_later(account.id)
      account
    end

    private

    # IG-Login returns the IG user id directly. FB-Login does not, so we look up
    # the Page the operator administers and read its linked IG business account.
    def resolve_identity(data)
      return { ig_user_id: data[:ig_user_id], page_id: data[:page_id] } if data[:ig_user_id]

      client = Client.new(access_token: data[:access_token], config: @config)
      page = candidate_pages(client).find { |p| p["instagram_business_account"] }
      unless page
        raise ConfigurationError,
          "connected, but no Page with a linked Instagram business account was found — " \
          "checked the Pages this token can list and the assets it was granted"
      end

      { ig_user_id: page.dig("instagram_business_account", "id").to_s, page_id: page["id"].to_s }
    end

    # /me/accounts lists only the Pages a token may enumerate, and a Page granted
    # through the Login-for-Business asset picker is not one of them — the list
    # comes back empty while the Page itself reads fine. So when the listing has
    # nothing usable, ask the token which assets it carries and read those.
    def candidate_pages(client)
      listed = client.list_pages
      unless listed.success?
        raise ApiError, "could not read Pages from Instagram: #{listed.error_message}"
      end

      pages = Array(listed.data["data"])
      return pages if pages.any? { |p| p["instagram_business_account"] }

      client.granted_asset_ids.filter_map do |id|
        result = client.page(id)
        result.data if result.success?
      end
    end
  end
end

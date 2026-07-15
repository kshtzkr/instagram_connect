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
      account
    end

    private

    # IG-Login returns the IG user id directly. FB-Login does not, so we look up
    # the Page the operator administers and read its linked IG business account.
    def resolve_identity(data)
      return { ig_user_id: data[:ig_user_id], page_id: data[:page_id] } if data[:ig_user_id]

      result = Client.new(access_token: data[:access_token], config: @config).list_pages
      page = Array(result.data["data"]).find { |p| p["instagram_business_account"] }
      raise ConfigurationError, "no Instagram business account is linked to a Page" unless page

      { ig_user_id: page.dig("instagram_business_account", "id"), page_id: page["id"] }
    end
  end
end

module InstagramConnect
  # A connected Instagram professional account. Holds the (encrypted) access
  # token and the identity the Graph client sends as. One row per connected
  # account — the gem supports connecting several.
  class Account < ApplicationRecord
    self.table_name = "instagram_connect_accounts"

    has_many :conversations, class_name: "InstagramConnect::Conversation",
             foreign_key: :account_id, dependent: :destroy
    has_many :comments, class_name: "InstagramConnect::Comment",
             foreign_key: :account_id, dependent: :destroy

    validates :ig_user_id, presence: true, uniqueness: true
    validates :auth_path, presence: true

    scope :active, -> { where(active: true) }
    scope :token_expiring_before, ->(time) { where.not(token_expires_at: nil).where(token_expires_at: ..time) }

    # Called from the engine initializer (and specs) when token encryption is
    # enabled. Kept as an explicit toggle so a host without Active Record
    # Encryption configured can opt out via config.encrypt_tokens = false.
    def self.enable_token_encryption!
      encrypts :access_token
      encrypts :page_access_token
    end

    # Every Instagram messaging call and the webhook subscription are Page-token
    # operations. Falling back to the user token keeps a freshly connected
    # account working until the readiness pass swaps in the Page one.
    def api_token
      page_access_token.presence || access_token
    end

    # The only place a Client should be built. Constructing one directly picks
    # up the *global* auth path, which is wrong for any host with accounts on
    # both paths — and wrong silently, which is worse.
    def client
      InstagramConnect::Client.new(
        access_token: api_token,
        ig_user_id: ig_user_id,
        config: InstagramConnect.configuration.for_auth_path(auth_path)
      )
    end

    def subscribed_field_list
      subscribed_fields.to_s.split(",").map(&:strip).reject(&:empty?)
    end

    def token_expired?
      token_expires_at.present? && token_expires_at <= Time.current
    end

    # Refresh via the account's auth strategy and persist the rotated token.
    # Refreshes via the strategy this row was connected with, not the globally
    # configured one.
    def refresh_access_token!
      strategy = InstagramConnect::Auth.for(InstagramConnect.configuration.for_auth_path(auth_path))
      data = strategy.refresh_token(access_token: access_token)
      update!(access_token: data[:access_token], token_expires_at: data[:expires_at])
    end
  end
end

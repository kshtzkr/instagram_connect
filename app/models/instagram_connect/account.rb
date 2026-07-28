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

    # An Active Record Encryption envelope, as stored. With
    # support_unencrypted_data on, a decrypt that FAILS (rotated or missing
    # keys) hands the envelope back instead of raising — so an unreadable
    # token reaches Meta as this JSON blob and comes back as the baffling
    # "Cannot parse access token", with every call dead and nothing saying why.
    ENCRYPTED_ENVELOPE = /\A\{"p":/

    # Every Instagram messaging call and the webhook subscription are Page-token
    # operations. Falling back to the user token keeps a freshly connected
    # account working until the readiness pass swaps in the Page one.
    def api_token
      page_access_token.presence || access_token
    end

    # False when the stored token cannot be decrypted with the keys this
    # process has. Recovery is always the same: reconnect the account, which
    # writes fresh tokens under the current keys.
    def token_readable?
      token = api_token.to_s
      token.present? && !token.match?(ENCRYPTED_ENVELOPE)
    rescue ActiveRecord::Encryption::Errors::Base => e
      # With previous-keys wired, a value no key set opens RAISES on read
      # (AEAD tag verification) instead of returning ciphertext — production
      # 500'd inside this very guard. Unreadable is unreadable, however the
      # encryption layer chooses to say it.
      Rails.logger.error("[instagram_connect] token read raised #{e.class} for account=#{id}")
      false
    end

    TOKEN_UNREADABLE_MESSAGE =
      "Stored access token cannot be decrypted with the current encryption " \
      "keys — reconnect this Instagram account to store a fresh one.".freeze

    # The only place a Client should be built. Constructing one directly picks
    # up the *global* auth path, which is wrong for any host with accounts on
    # both paths — and wrong silently, which is worse.
    def client
      # Refuse to build a client around a token Meta can only reject, and
      # record WHY on the row so the host's health screen can say it out loud
      # instead of every screen quietly rendering empty.
      unless token_readable?
        update_columns(readiness_error: TOKEN_UNREADABLE_MESSAGE.truncate(255))
        raise InstagramConnect::TokenUnreadableError, TOKEN_UNREADABLE_MESSAGE
      end

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

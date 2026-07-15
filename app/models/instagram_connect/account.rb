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
    end

    def token_expired?
      token_expires_at.present? && token_expires_at <= Time.current
    end

    # Refresh via the account's auth strategy and persist the rotated token.
    def refresh_access_token!
      data = InstagramConnect::Auth.for(InstagramConnect.configuration).refresh_token(access_token: access_token)
      update!(access_token: data[:access_token], token_expires_at: data[:expires_at])
    end
  end
end

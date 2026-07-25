module InstagramConnect
  # One rate-limit bucket for one account, for one window.
  class ApiBudget < ApplicationRecord
    self.table_name = "instagram_connect_api_budgets"

    belongs_to :account, class_name: "InstagramConnect::Account"

    validates :bucket, :window_start, :window_seconds, :limit_value, presence: true

    def window_end
      window_start + window_seconds
    end

    def blocked?
      blocked_until.present? && blocked_until > Time.current
    end

    def exhausted?
      used >= limit_value
    end
  end
end

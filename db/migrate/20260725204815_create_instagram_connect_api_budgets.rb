class CreateInstagramConnectApiBudgets < ActiveRecord::Migration[7.1]
  # A shared, durable counter per account per rate-limit bucket.
  #
  # Meta's limits are per Instagram account, not per process, so a counter held
  # in memory is wrong the moment there is more than one worker — and resets to
  # zero on every deploy, which is exactly when a backlog is most likely to
  # burst through the ceiling. A row with a unique key on the window makes the
  # increment atomic across processes in one statement.
  def change
    create_table :instagram_connect_api_budgets, if_not_exists: true do |t|
      t.bigint :account_id, null: false
      t.string :bucket, null: false
      t.datetime :window_start, null: false
      t.integer :window_seconds, null: false
      t.integer :used, null: false, default: 0
      t.integer :limit_value, null: false
      # Set when Meta says outright that we are throttled. Until it passes,
      # every job for this account refuses immediately rather than each one
      # rediscovering the block for itself.
      t.datetime :blocked_until
      t.timestamps
    end

    add_index :instagram_connect_api_budgets, [ :account_id, :bucket, :window_start ],
              unique: true, name: "index_instagram_connect_budgets_unique", if_not_exists: true
    add_index :instagram_connect_api_budgets, [ :account_id, :bucket, :blocked_until ],
              name: "index_instagram_connect_budgets_on_blocked", if_not_exists: true
  end
end

class CreateInstagramConnectInsightSnapshots < ActiveRecord::Migration[7.1]
  # Metric readings, kept because Meta does not keep them for long: story
  # metrics are retrievable for 24 hours, account metrics for 90 days, media
  # metrics for two years. A dashboard reading straight from the API can only
  # ever show that window.
  #
  # Story insights are the acute case. The `story_insights` webhook fires when a
  # story expires and carries its final metrics — that delivery is the only
  # chance to record them, so its handler writes here synchronously rather than
  # deferring to a job that might not run in time.
  def change
    create_table :instagram_connect_insight_snapshots, if_not_exists: true do |t|
      t.bigint :account_id, null: false
      t.string :subject_type, null: false
      t.string :subject_ref
      t.string :period, null: false
      t.date :period_start, null: false
      t.string :breakdown
      # webhook | api. Part of the uniqueness key so the poller overwrites its
      # own readings all day without ever colliding with the webhook's final
      # one, and a dropped webhook still leaves the last mid-life reading.
      t.string :source, null: false, default: "api"
      t.column :metrics, json_type, null: false
      # A metric Meta declines to report is absent from metrics rather than
      # zero — these flags are how a UI tells "not reported" from "really zero".
      t.boolean :empty, null: false, default: false
      t.boolean :suppressed, null: false, default: false
      t.integer :error_code
      t.datetime :captured_at, null: false
      t.timestamps
    end

    add_index :instagram_connect_insight_snapshots,
              [ :account_id, :subject_type, :subject_ref, :period, :period_start, :breakdown, :source ],
              unique: true, name: "index_instagram_connect_snapshots_unique", if_not_exists: true
    add_index :instagram_connect_insight_snapshots, [ :account_id, :captured_at ],
              name: "index_instagram_connect_snapshots_on_account_and_time", if_not_exists: true
  end

  private

  def json_type
    connection.adapter_name.match?(/postg/i) ? :jsonb : :json
  end
end

class CreateInstagramConnectWebhookEvents < ActiveRecord::Migration[7.1]
  # Every webhook event Meta delivers, stored verbatim before anything tries to
  # interpret it.
  #
  # Meta does not store `mentions` or `story_insights` notifications and never
  # re-delivers any event, so a parse bug against a live payload is permanent
  # data loss. With this table it is a re-runnable row instead. It also lets an
  # operator subscribe a field at Meta before its handler exists — the events
  # bank as "unhandled" and ReplayEventsJob walks them once the handler ships.
  def change
    create_table :instagram_connect_webhook_events, if_not_exists: true do |t|
      # Nullable: an entry whose id matches no connected account is recorded
      # rather than dropped. That is how you discover a second Page was
      # connected to the app, instead of losing a week of DMs to a counter.
      t.bigint :account_id
      t.string :object
      t.string :field, null: false
      t.string :event_type, null: false
      t.string :dedupe_key, null: false
      t.string :entry_id
      t.datetime :occurred_at
      t.datetime :received_at, null: false
      t.datetime :processed_at
      t.string :status, null: false, default: "pending"
      t.string :handler
      t.string :error_class
      t.text :error_message
      t.integer :attempts, null: false, default: 0
      t.string :subject_type
      t.bigint :subject_id
      t.column :payload, json_type, null: false
      t.timestamps
    end

    add_index :instagram_connect_webhook_events, [ :field, :dedupe_key ],
              unique: true, if_not_exists: true
    add_index :instagram_connect_webhook_events, [ :account_id, :field, :occurred_at ],
              name: "index_instagram_connect_webhook_events_on_account_field_time",
              if_not_exists: true
    add_index :instagram_connect_webhook_events, [ :status, :created_at ], if_not_exists: true
    add_index :instagram_connect_webhook_events, [ :subject_type, :subject_id ], if_not_exists: true
  end

  private

  # The gem ships into whichever database the host runs. jsonb is the right
  # column on Postgres and does not exist on SQLite, so pick per adapter rather
  # than forcing every adopter onto one.
  def json_type
    connection.adapter_name.match?(/postg/i) ? :jsonb : :json
  end
end

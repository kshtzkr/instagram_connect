class AddOutboundSendFields < ActiveRecord::Migration[7.1]
  # Individual add_column calls rather than a bulk change_table: only add_column
  # honours if_not_exists, and every migration this gem ships has to survive
  # being re-run against a database that already has the columns.
  COLUMNS = {
    # A message over Meta's 1000-byte ceiling goes out as several sends. This
    # is the resume cursor, so a worker killed mid-fan-out picks up where it
    # stopped instead of repeating parts the customer already received.
    delivered_parts_count: { type: :integer, default: 0, null: false },
    # The reusable id Meta returns from the Attachment Upload API, so a canned
    # reply image is uploaded once and sent by reference afterwards.
    attachment_upload_id: { type: :string }
  }.freeze

  def change
    COLUMNS.each do |name, options|
      add_column :instagram_connect_messages, name, options[:type],
                 **options.except(:type), if_not_exists: true
    end

    # Composer idempotency: a double-submit carries the same token and the
    # unique index turns the second one into a no-op rather than a second
    # bubble the customer sees twice.
    add_column :instagram_connect_messages, :client_token, :string, if_not_exists: true
    add_index :instagram_connect_messages, :client_token, unique: true, if_not_exists: true
  end
end

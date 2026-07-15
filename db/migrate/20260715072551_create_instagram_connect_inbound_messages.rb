class CreateInstagramConnectInboundMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :instagram_connect_inbound_messages, if_not_exists: true do |t|
      t.string :ig_message_id, null: false
      t.bigint :account_id
      t.datetime :processed_at
      t.timestamps
    end
    add_index :instagram_connect_inbound_messages, :ig_message_id, unique: true, if_not_exists: true
  end
end

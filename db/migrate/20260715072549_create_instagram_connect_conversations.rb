class CreateInstagramConnectConversations < ActiveRecord::Migration[7.1]
  def change
    create_table :instagram_connect_conversations do |t|
      t.bigint :account_id, null: false
      t.string :igsid, null: false
      t.string :username
      t.string :display_name
      t.datetime :last_message_at
      t.datetime :last_inbound_at
      t.string :last_message_preview
      t.integer :unread_count, default: 0, null: false
      t.timestamps
    end
    add_index :instagram_connect_conversations, [ :account_id, :igsid ], unique: true
  end
end

class CreateInstagramConnectMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :instagram_connect_messages, if_not_exists: true do |t|
      t.bigint :conversation_id, null: false
      t.string :direction, null: false
      t.string :status, null: false
      t.string :kind, default: "dm", null: false
      t.string :source
      t.text :body
      t.string :ig_message_id
      t.string :message_tag
      t.bigint :sent_by_id
      t.string :media_status, default: "none", null: false
      t.string :media_mime
      t.string :media_filename
      t.integer :media_size
      t.string :media_error
      t.string :error_message
      t.string :failure_reason
      t.timestamps
    end
    add_index :instagram_connect_messages, :conversation_id, if_not_exists: true
    add_index :instagram_connect_messages, :ig_message_id, unique: true, if_not_exists: true
  end
end

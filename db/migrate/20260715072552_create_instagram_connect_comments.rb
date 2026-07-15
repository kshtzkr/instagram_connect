class CreateInstagramConnectComments < ActiveRecord::Migration[7.1]
  def change
    create_table :instagram_connect_comments, if_not_exists: true do |t|
      t.bigint :account_id, null: false
      t.string :media_id
      t.string :comment_id, null: false
      t.string :parent_id
      t.string :from_username
      t.text :text
      t.datetime :hidden_at
      t.datetime :replied_at
      t.timestamps
    end
    add_index :instagram_connect_comments, :comment_id, unique: true, if_not_exists: true
    add_index :instagram_connect_comments, :account_id, if_not_exists: true
  end
end

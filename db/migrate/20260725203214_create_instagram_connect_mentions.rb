class CreateInstagramConnectMentions < ActiveRecord::Migration[7.1]
  # Every @mention of the account — in a comment, in a caption, or as a tag.
  #
  # This is a table rather than a query because **Meta does not store mention
  # notifications**. There is no endpoint to ask "what did I miss": the webhook
  # is delivered once and if it is not written down at that moment it is gone.
  # For a travel brand these are the highest-value events on the platform —
  # customers posting photos of a trip we sold them.
  def change
    create_table :instagram_connect_mentions, if_not_exists: true do |t|
      t.bigint :account_id, null: false
      t.string :kind, null: false
      t.string :ig_media_id
      t.string :comment_id
      t.bigint :message_id
      t.string :from_username
      t.text :text
      t.text :permalink
      t.datetime :mentioned_at, null: false
      t.datetime :replied_at
      t.string :reply_comment_id
      t.timestamps
    end

    add_index :instagram_connect_mentions, [ :account_id, :kind, :ig_media_id, :comment_id ],
              unique: true, name: "index_instagram_connect_mentions_unique", if_not_exists: true
    add_index :instagram_connect_mentions, [ :account_id, :mentioned_at ],
              name: "index_instagram_connect_mentions_on_account_and_time", if_not_exists: true
  end
end

class CreateInstagramConnectMedia < ActiveRecord::Migration[7.1]
  # Our own record of the account's posts, reels and stories.
  #
  # It exists because insights and mentions both need something to hang off, and
  # because a story is gone from the API 24 hours after it is posted — the row
  # has to outlive the thing it describes.
  def change
    create_table :instagram_connect_media, if_not_exists: true do |t|
      t.bigint :account_id, null: false
      t.string :ig_media_id, null: false
      t.string :media_type
      # FEED | STORY | REELS | AD. Distinct from media_type, and the field that
      # decides which insight metrics Meta will even accept.
      t.string :media_product_type
      t.text :caption
      t.text :permalink
      t.text :media_url
      t.text :thumbnail_url
      t.datetime :posted_at
      t.integer :comments_count
      t.integer :like_count
      t.datetime :synced_at
      t.timestamps
    end

    add_index :instagram_connect_media, [ :account_id, :ig_media_id ],
              unique: true, if_not_exists: true
    add_index :instagram_connect_media, [ :account_id, :posted_at ], if_not_exists: true
  end
end

class AddConversationProfileFields < ActiveRecord::Migration[7.1]
  # username and display_name already existed on conversations and nothing ever
  # wrote them, so an inbox showed raw Instagram-scoped ids — a 17-digit number
  # where a person's handle belongs. These are the rest of what a thread row
  # needs to look like a conversation with somebody.
  def change
    add_column :instagram_connect_conversations, :profile_picture_url, :text, if_not_exists: true
    add_column :instagram_connect_conversations, :profile_synced_at, :datetime, if_not_exists: true

    # Partial indexes are Postgres-only, and this gem ships into whatever
    # database the host runs.
    add_index :instagram_connect_conversations, [ :account_id, :profile_synced_at ],
              name: "index_instagram_connect_conversations_on_profile_sync",
              if_not_exists: true

    # Cheap header stats, and the input to the 4800 x impressions budget the
    # rate limiter falls back on when Meta sends no usage header.
    add_column :instagram_connect_accounts, :followers_count, :integer, if_not_exists: true
    add_column :instagram_connect_accounts, :media_count, :integer, if_not_exists: true
  end
end

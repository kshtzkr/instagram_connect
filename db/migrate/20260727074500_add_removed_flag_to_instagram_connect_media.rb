class AddRemovedFlagToInstagramConnectMedia < ActiveRecord::Migration[7.1]
  # Instagram sends no webhook when a post is deleted; absence from the
  # account's own completed listing is the only signal there is. A vanished
  # post is stamped, never destroyed — hosts render it as a locked, grayed,
  # still-viewable row.
  #
  # if_not_exists because one host added this column app-side before the gem
  # owned it; re-running here must be a no-op there.
  def change
    add_column :instagram_connect_media, :removed_from_instagram_at, :datetime,
               if_not_exists: true
  end
end

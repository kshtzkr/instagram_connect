class AddChildrenToInstagramConnectMedia < ActiveRecord::Migration[8.0]
  # The slides of a carousel post, as Meta returns them: an array of
  # {id, media_type, media_url, thumbnail_url} hashes. json, not jsonb,
  # because the gem runs on sqlite too. if_not_exists so a host that ran a
  # copy of this migration before adopting the gem version is unaffected.
  def change
    add_column :instagram_connect_media, :children, :json, if_not_exists: true
  end
end

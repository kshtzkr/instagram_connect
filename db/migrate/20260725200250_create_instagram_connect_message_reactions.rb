class CreateInstagramConnectMessageReactions < ActiveRecord::Migration[7.1]
  # An append-only log of reactions, not a current-state table.
  #
  # Meta guarantees no ordering across webhook batches, so react → unreact →
  # react can arrive in any sequence. Storing each event and reading the latest
  # by reacted_at self-corrects; storing "the" reaction on the message would
  # let a late unreact clear a reaction the customer has since re-added.
  def change
    create_table :instagram_connect_message_reactions, if_not_exists: true do |t|
      t.bigint :conversation_id, null: false
      # Nullable: a reaction can arrive before the message it belongs to, and
      # can point at a message that predates this install entirely.
      t.bigint :message_id
      t.string :ig_message_id, null: false
      t.string :igsid, null: false
      t.string :actor, null: false
      t.string :action, null: false
      t.string :reaction
      t.string :emoji
      t.datetime :reacted_at, null: false
      t.timestamps
    end

    add_index :instagram_connect_message_reactions, [ :conversation_id, :reacted_at ],
              name: "index_instagram_connect_reactions_on_conversation_and_time",
              if_not_exists: true
    add_index :instagram_connect_message_reactions, :ig_message_id, if_not_exists: true
    add_index :instagram_connect_message_reactions, :message_id, if_not_exists: true
  end
end

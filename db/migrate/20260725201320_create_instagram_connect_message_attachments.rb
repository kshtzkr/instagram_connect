class CreateInstagramConnectMessageAttachments < ActiveRecord::Migration[7.1]
  # One row per file on a message, rather than the single set of media_* columns
  # the messages table already carries.
  #
  # A DM can hold up to ten images, and each one fetches independently: one job
  # per attachment means a ten-image message does not serialise behind the
  # slowest file, and a retry ladder isolates to the file that actually failed.
  def change
    create_table :instagram_connect_message_attachments, if_not_exists: true do |t|
      t.bigint :message_id, null: false
      t.integer :position, null: false
      t.string :kind, null: false
      # Meta's CDN URL. Short-lived and not re-requestable, which is why the
      # bytes are copied into the host's own storage rather than linked.
      t.text :source_url
      t.string :state, null: false, default: "pending"
      t.string :mime
      t.string :filename
      t.bigint :size
      t.string :error
      # A reusable id from Meta's Attachment Upload API, so a canned reply image
      # is uploaded once and sent by reference thereafter.
      t.string :ig_attachment_id
      t.timestamps
    end

    add_index :instagram_connect_message_attachments, [ :message_id, :position ],
              unique: true, if_not_exists: true
    add_index :instagram_connect_message_attachments, [ :state, :created_at ],
              name: "index_instagram_connect_attachments_on_state_and_time",
              if_not_exists: true
  end
end

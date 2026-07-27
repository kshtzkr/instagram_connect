class AddAttachmentDeliveredAtToMessages < ActiveRecord::Migration[8.0]
  # The resume cursor for the attachment half of a send, mirroring
  # delivered_parts_count for the text half: a worker killed between the
  # attachment and the text must not send the photo twice.
  def change
    add_column :instagram_connect_messages, :attachment_delivered_at, :datetime,
               if_not_exists: true
  end
end

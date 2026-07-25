class AddCommentModerationFields < ActiveRecord::Migration[7.1]
  COLUMNS = {
    # The commenter's Instagram-scoped id. Needed to send them a private reply,
    # which the username alone cannot address.
    from_ig_id: { type: :string },
    commented_at: { type: :datetime },
    like_count: { type: :integer },
    # From the live_comments field. A private reply to a live comment is valid
    # only while the broadcast is running, so this is what stops the UI offering
    # a button that is already guaranteed to fail.
    is_live: { type: :boolean, default: false, null: false },
    deleted_at: { type: :datetime },
    # Distinct from replied_at, which is a public reply. The private reply is a
    # separate, spendable resource: one per commenter, expiring 7 days after the
    # comment.
    private_replied_at: { type: :datetime },
    private_reply_message_id: { type: :bigint }
  }.freeze

  def change
    COLUMNS.each do |name, options|
      add_column :instagram_connect_comments, name, options[:type],
                 **options.except(:type), if_not_exists: true
    end

    add_index :instagram_connect_comments, [ :account_id, :commented_at ],
              name: "index_instagram_connect_comments_on_account_and_time", if_not_exists: true
  end
end

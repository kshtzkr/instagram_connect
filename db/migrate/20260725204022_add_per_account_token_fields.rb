class AddPerAccountTokenFields < ActiveRecord::Migration[7.1]
  ACCOUNT_COLUMNS = {
    # The OAuth exchange returns a *user* token, but every Instagram messaging
    # endpoint and the webhook subscription are Page-token operations. Keeping
    # them in separate columns is what lets the readiness pass tell which grade
    # it is holding instead of guessing.
    page_access_token: { type: :text },
    page_token_verified_at: { type: :datetime },
    # Set when a Page call comes back with an auth error. There is no silent
    # recovery from this — the operator has to reconnect — so it surfaces as a
    # flag rather than as a retry that can never succeed.
    needs_reconnect: { type: :boolean, default: false, null: false },
    readiness_error: { type: :string },
    # The fields the Page is actually subscribed to, as last read from Meta.
    # Lets the readiness pass skip a POST it does not need, and lets a health
    # screen show what is really live rather than what we hoped.
    subscribed_fields: { type: :text },
    subscriptions_synced_at: { type: :datetime },
    name: { type: :string },
    profile_picture_url: { type: :text },
    profile_synced_at: { type: :datetime }
  }.freeze

  def change
    ACCOUNT_COLUMNS.each do |name, options|
      add_column :instagram_connect_accounts, name, options[:type],
                 **options.except(:type), if_not_exists: true
    end

    add_column :instagram_connect_messages, :account_id, :bigint, if_not_exists: true

    reversible do |dir|
      dir.up { backfill_message_accounts }
    end

    # Uniqueness has to be per account, not global. With two connected accounts
    # that message each other, the echo's mid is claimed by whichever processes
    # first and permanently dropped for the other — a live correctness bug, not
    # hygiene. Same reasoning for comments and the inbound ledger.
    add_index :instagram_connect_messages, [ :account_id, :ig_message_id ],
              unique: true, name: "index_instagram_connect_messages_on_account_and_mid",
              if_not_exists: true
    remove_index :instagram_connect_messages, column: :ig_message_id, if_exists: true

    add_index :instagram_connect_comments, [ :account_id, :comment_id ],
              unique: true, name: "index_instagram_connect_comments_on_account_and_comment",
              if_not_exists: true
    remove_index :instagram_connect_comments, column: :comment_id, if_exists: true

    add_index :instagram_connect_inbound_messages, [ :account_id, :ig_message_id ],
              unique: true, name: "index_instagram_connect_inbound_on_account_and_mid",
              if_not_exists: true
    remove_index :instagram_connect_inbound_messages, column: :ig_message_id, if_exists: true
  end

  private

  # Denormalized from the conversation so account-scoped inbox queries and
  # stream names do not need a join. Filled inline because the new unique index
  # is only meaningful once it is populated — a NULL account_id would let the
  # very duplicates this index exists to prevent slip through.
  #
  # A correlated subquery rather than UPDATE...FROM, which is Postgres-only.
  # An adopter with millions of messages should run this chunked before
  # upgrading; at the scale this gem is written for it is a single indexed pass.
  def backfill_message_accounts
    execute(<<~SQL.squish)
      UPDATE instagram_connect_messages
      SET account_id = (
        SELECT account_id FROM instagram_connect_conversations
        WHERE instagram_connect_conversations.id = instagram_connect_messages.conversation_id
      )
      WHERE account_id IS NULL
    SQL
  end
end

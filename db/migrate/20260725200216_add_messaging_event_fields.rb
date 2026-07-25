class AddMessagingEventFields < ActiveRecord::Migration[7.1]
  # Columns for the messaging events beyond plain DMs — reactions, read
  # receipts, referrals, thread handover, quick replies, story replies — plus
  # the wire clock all of their ordering depends on.
  #
  # Written as individual add_column calls rather than a bulk change_table
  # because only add_column honours if_not_exists, and every migration this gem
  # ships has to survive being re-run against a database that already has the
  # columns (0.2.1 shipped to fix exactly that).
  MESSAGE_COLUMNS = {
    # Meta's own timestamp. Ordering used our created_at, so a webhook batch
    # delayed by a redeploy silently reordered a thread. Backfilled below, and
    # left nullable on purpose: promoting it to NOT NULL takes a lock this gem
    # cannot know the cost of in an adopter's database.
    sent_at: { type: :datetime },
    seen_at: { type: :datetime },
    # The customer unsent the message. The row is never destroyed — the thread
    # should read "message unsent" rather than lose its shape. Erasing it is a
    # host policy decision, not a gem default.
    deleted_at: { type: :datetime },
    unsupported: { type: :boolean, default: false, null: false },
    reply_to_mid: { type: :string },
    quick_reply_payload: { type: :string },
    postback_payload: { type: :string },
    postback_title: { type: :string },
    referral_ref: { type: :string },
    referral_source: { type: :string },
    referral_type: { type: :string },
    referral_product_id: { type: :string },
    story_id: { type: :string },
    story_url: { type: :text },
    # The wire attachment type (image, video, story_mention, ig_reel...),
    # orthogonal to the MIME type of the bytes behind it.
    media_kind: { type: :string },
    # Projections of the reaction log, so a bubble renders without a join.
    reactions_count: { type: :integer, default: 0, null: false },
    last_reaction: { type: :string }
  }.freeze

  CONVERSATION_COLUMNS = {
    # Meta splits threads into primary/general/requests. A requests thread idle
    # for 30 days stops being returned by the Conversations API at all, so the
    # folder is how the UI explains a thread it can never re-fetch.
    folder: { type: :string },
    customer_last_read_at: { type: :datetime },
    customer_last_read_mid: { type: :string },
    # Which app currently owns the thread. If the Page Inbox holds control, our
    # Send API call fails — a send has to read this rather than discover it as
    # an opaque API error.
    thread_owner_app_id: { type: :string },
    thread_control_at: { type: :datetime },
    last_referral_ref: { type: :string },
    # Any event at all, including ones that are not messages. Distinct from
    # last_message_at so a quiet-but-active thread still sorts sensibly.
    last_event_at: { type: :datetime }
  }.freeze

  def change
    MESSAGE_COLUMNS.each do |name, options|
      add_column :instagram_connect_messages, name, options[:type],
                 **options.except(:type), if_not_exists: true
    end

    CONVERSATION_COLUMNS.each do |name, options|
      add_column :instagram_connect_conversations, name, options[:type],
                 **options.except(:type), if_not_exists: true
    end

    add_index :instagram_connect_messages, :sent_at, if_not_exists: true
    add_index :instagram_connect_messages, :reply_to_mid, if_not_exists: true

    reversible do |dir|
      dir.up { backfill_sent_at }
    end
  end

  private

  # Existing rows predate the column and every ordering now reads it. Rather
  # than leave them NULL and make every query COALESCE, seed them with the only
  # timestamp we have.
  def backfill_sent_at
    execute(<<~SQL.squish)
      UPDATE instagram_connect_messages
      SET sent_at = created_at
      WHERE sent_at IS NULL
    SQL
  end
end

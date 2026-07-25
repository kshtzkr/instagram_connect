module InstagramConnect
  class Ingest
    # Maps a webhook field to the handler that parses it, and infers the field
    # for messaging events (Meta delivers all of them under `entry.messaging`
    # regardless of which subscription triggered them, so the field has to be
    # recovered from the event's shape).
    module Registry
      HANDLERS = {
        "messages" => Handlers::Messages,
        "message_echoes" => Handlers::Messages,
        "messaging_postbacks" => Handlers::MessagingPostbacks,
        "message_reactions" => Handlers::MessageReactions,
        "messaging_seen" => Handlers::MessagingSeen,
        "messaging_referral" => Handlers::MessagingReferral,
        "messaging_optins" => Handlers::MessagingOptins,
        "messaging_handover" => Handlers::MessagingHandover,
        "comments" => Handlers::Comments,
        "live_comments" => Handlers::Comments
      }.freeze

      # Every field the gem knows Meta can send on the `instagram` object.
      # Fields without a handler are still worth subscribing to: they bank as
      # `unhandled` rows and replay once a handler ships, whereas an
      # unsubscribed field is gone for good — Meta does not store `mentions` or
      # `story_insights` notifications, and re-delivers nothing.
      KNOWN_FIELDS = %w[
        messages
        message_echoes
        message_reactions
        messaging_postbacks
        messaging_seen
        messaging_referral
        messaging_optins
        messaging_handover
        messaging_policy_enforcement
        response_feedback
        standby
        comments
        live_comments
        mentions
        story_insights
      ].freeze

      # Shape tests in priority order. `is_echo` must be checked before the
      # plain `message` case, since an echo carries a message too.
      MESSAGING_SHAPES = [
        [ "message_echoes", ->(e) { e["message"] && e.dig("message", "is_echo") } ],
        [ "messages", ->(e) { e["message"] } ],
        [ "message_reactions", ->(e) { e["reaction"] } ],
        [ "messaging_postbacks", ->(e) { e["postback"] } ],
        [ "messaging_seen", ->(e) { e["read"] } ],
        [ "messaging_referral", ->(e) { e["referral"] } ],
        [ "messaging_optins", ->(e) { e["optin"] } ],
        [ "messaging_handover", lambda { |e|
          e["pass_thread_control"] || e["take_thread_control"] || e["request_thread_control"]
        } ]
      ].freeze

      UNKNOWN_FIELD = "unknown".freeze

      module_function

      def handler_for(field)
        HANDLERS.fetch(field, Handlers::Unknown)
      end

      def handled?(field)
        HANDLERS.key?(field)
      end

      # The fields a host should subscribe its Page to. Everything the gem
      # knows about, handled or not — see KNOWN_FIELDS.
      def subscribable_fields
        KNOWN_FIELDS
      end

      def handled_fields
        HANDLERS.keys
      end

      # `message.referral` and `postback.referral` are nested inside their
      # parent event and stay with it; only a standalone `referral` is a
      # referral event in its own right, which is why the shape tests run in
      # order rather than checking every key independently.
      def messaging_field_for(event)
        found = MESSAGING_SHAPES.find { |(_field, test)| test.call(event) }
        found ? found.first : UNKNOWN_FIELD
      end
    end
  end
end

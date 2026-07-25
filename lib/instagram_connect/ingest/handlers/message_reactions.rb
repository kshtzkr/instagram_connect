module InstagramConnect
  class Ingest
    module Handlers
      # A customer reacting to (or un-reacting from) a message.
      #
      # Reactions also reopen the 24-hour messaging window, which is why they
      # bump the conversation's activity even though they are not messages.
      class MessageReactions < Base
        # A customer can react, unreact, then react again with the same emoji on
        # the same message. Those are three real events sharing a mid, so the
        # action and the wire timestamp both belong in the key. A genuine
        # redelivery repeats the timestamp and still collapses, which is the
        # distinction that matters.
        def self.dedupe_key(event)
          reaction = event["reaction"] || {}
          mid = reaction["mid"].presence or return nil

          [ mid, reaction["action"], reaction["reaction"], event["timestamp"] ].compact.join(":")
        end

        def call
          record = InstagramConnect::MessageReaction.create!(
            conversation: conversation,
            message: message,
            ig_message_id: mid,
            igsid: igsid,
            actor: actor,
            action: action,
            reaction: payload["reaction"],
            emoji: payload["emoji"],
            reacted_at: reacted_at
          )
          refresh_message_projection
          conversation.register_event(reacted_at)
          record
        end

        private

        def payload
          event["reaction"] || {}
        end

        def mid
          payload["mid"].to_s
        end

        def action
          payload["action"] == "unreact" ? "unreact" : "react"
        end

        # A reaction the business left shows up as an event from the account
        # itself rather than from the customer.
        def actor
          igsid == account.ig_user_id ? "business" : "customer"
        end

        def igsid
          event.dig("sender", "id").to_s
        end

        def reacted_at
          envelope.occurred_at || Time.current
        end

        def message
          @message ||= InstagramConnect::Message.find_by(ig_message_id: mid)
        end

        def conversation
          @conversation ||= message&.conversation ||
            InstagramConnect::Conversation.locate(account: account, igsid: igsid)
        end

        # Denormalized onto the message so a bubble renders without a join.
        # Recomputed from the log rather than incremented, so an out-of-order
        # unreact cannot leave the projection disagreeing with its source.
        def refresh_message_projection
          return if message.nil?

          current = InstagramConnect::MessageReaction.current_for(mid)
          InstagramConnect::Message.where(id: message.id).update_all(
            reactions_count: InstagramConnect::MessageReaction.where(ig_message_id: mid, action: "react").count,
            last_reaction: current&.reaction,
            updated_at: Time.current
          )
        end
      end
    end
  end
end

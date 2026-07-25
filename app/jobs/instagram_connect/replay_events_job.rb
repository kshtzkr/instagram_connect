module InstagramConnect
  # Re-runs banked webhook events through the current handlers.
  #
  # This is the payoff for storing raw payloads. Two situations need it, and
  # neither is recoverable any other way, because Meta does not re-deliver:
  #
  #   - A field was subscribed before the gem could parse it. Its events banked
  #     as `unhandled`; once the handler ships, replay them and the history is
  #     complete rather than starting from the deploy.
  #   - A handler had a bug. The events are marked `failed` with the error;
  #     fix the bug, replay, and no data was lost in between.
  #
  # Replaying is safe to repeat: handlers write through the same upserts and
  # unique indexes the live path uses.
  class ReplayEventsJob < ApplicationJob
    queue_as :default

    def perform(field: nil, since: nil, limit: 500, config: nil)
      configuration = config || InstagramConnect.configuration

      scope = WebhookEvent.replayable.chronological.limit(limit)
      scope = scope.for_field(field) if field.present?
      scope = scope.where(created_at: since..) if since.present?

      scope.find_each do |event|
        replay(event, configuration)
      end
    end

    private

    def replay(event, configuration)
      handler_class = Ingest::Registry.handler_for(event.field)
      unless Ingest::Registry.handled?(event.field) && event.account
        # Still nothing that can parse it — leave the row banked rather than
        # burning through the same backlog on every run.
        return
      end

      envelope = Ingest::Envelope.new(
        account: event.account, object: event.object, field: event.field,
        event_type: event.event_type, event: event.payload, entry_id: event.entry_id,
        occurred_at: event.occurred_at, config: configuration
      )
      handler = handler_class.new(envelope)
      event.increment!(:attempts)
      subject = handler.call
      event.mark_processed!(subject)
    rescue StandardError => e
      event.mark_failed!(e)
      configuration.logger&.error(
        "[InstagramConnect] replay failed for event=#{event.id} field=#{event.field}: " \
        "#{e.class}: #{e.message}"
      )
    end
  end
end

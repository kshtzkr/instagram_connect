require "digest"
require "json"

module InstagramConnect
  class Ingest
    # Walks a verified webhook payload, banks every event it contains on the
    # ledger, and routes each one to its handler.
    #
    # Two rules shape this class:
    #
    # 1. Nothing is dropped. An event with no handler, or belonging to no
    #    connected account, still gets a row. Meta does not re-deliver, so a
    #    counter increment would be the only record that something was lost.
    # 2. One bad event cannot poison the batch. Each is wrapped in its own
    #    rescue and marked `failed` with its error, leaving the rest to process.
    class Dispatcher
      def initialize(config)
        @config = config
      end

      def call(payload)
        summary = Summary.new
        Array(payload && payload["entry"]).each do |entry|
          process_entry(payload, entry, summary)
        end
        summary
      end

      private

      attr_reader :config

      def process_entry(payload, entry, summary)
        account = account_for(entry)
        entry_id = entry["id"].to_s
        occurred_at = Envelope.time_from(entry["time"])

        flatten(entry).each do |field, event|
          process_event(
            account: account, object: payload["object"], field: field, event: event,
            entry_id: entry_id, entry_time: occurred_at, summary: summary
          )
        end
      end

      # Messaging events arrive under `entry.messaging` whatever subscription
      # produced them, so their field is recovered by shape. `standby` wraps the
      # same shapes for a thread this app does not currently control. Changes
      # (comments, mentions, story insights) name their own field.
      def flatten(entry)
        pairs = Array(entry["messaging"]).map { |event| [ Registry.messaging_field_for(event), event ] }
        pairs += Array(entry["standby"]).map { |event| [ "standby", event ] }
        pairs + Array(entry["changes"]).map { |change| [ change["field"].to_s, change ] }
      end

      def process_event(account:, object:, field:, event:, entry_id:, entry_time:, summary:)
        handler_class = Registry.handler_for(field)
        key = dedupe_key(handler_class, field, event, entry_id)

        # A handler that needs Meta's id cannot do anything useful without one.
        # An event like this used to be counted as skipped; banking it means an
        # operator can see that Meta sent something malformed.
        if handler_class.respond_to?(:requires_dedupe_key?) && handler_class.requires_dedupe_key? &&
           handler_class.dedupe_key(event).blank?
          record_unhandled(account, object, field, event, entry_id, entry_time, key, summary)
          return
        end

        record = WebhookEvent.claim(
          account: account, object: object, field: field,
          event_type: field, dedupe_key: key, entry_id: entry_id,
          occurred_at: event_time(event) || entry_time, payload: event,
          handler: handler_class.name
        )

        if record.nil?
          summary.duplicates += 1
          return
        end

        if account.nil? || !Registry.handled?(field)
          record.mark_unhandled!
          summary.unhandled += 1
          return
        end

        run(handler_class, record, account, object, field, event, entry_id, entry_time, summary)
      end

      def run(handler_class, record, account, object, field, event, entry_id, entry_time, summary)
        envelope = Envelope.new(
          account: account, object: object, field: field, event_type: field,
          event: event, entry_id: entry_id,
          occurred_at: event_time(event) || entry_time, config: config
        )
        handler = handler_class.new(envelope)
        subject = handler.call
        record.mark_processed!(subject)
        summary.count(field)
        deliver(handler.notification, summary)
      rescue StandardError => e
        record.mark_failed!(e)
        summary.failed += 1
      end

      # The host callback runs outside the handler, in its own rescue. The rows
      # are already committed at this point, so a host hook raising must not
      # flip the event to failed — it would be replayed and duplicate the data.
      def deliver(notification, summary)
        return if notification.nil?

        handler, argument = notification
        handler.call(argument) if handler.respond_to?(:call)
      rescue StandardError => e
        summary.callback_errors += 1
        config.logger&.error("[InstagramConnect] host callback raised: #{e.class}: #{e.message}")
      end

      def record_unhandled(account, object, field, event, entry_id, entry_time, key, summary)
        record = WebhookEvent.claim(
          account: account, object: object, field: field, event_type: field,
          dedupe_key: key, entry_id: entry_id,
          occurred_at: event_time(event) || entry_time, payload: event,
          handler: Handlers::Unknown.name
        )
        if record.nil?
          summary.duplicates += 1
        else
          record.mark_unhandled!
          summary.unhandled += 1
        end
      end

      def dedupe_key(handler_class, field, event, entry_id)
        handler_class.dedupe_key(event).presence ||
          Digest::SHA256.hexdigest("#{field}:#{entry_id}:#{JSON.generate(event)}")
      end

      def event_time(event)
        Envelope.time_from(event["timestamp"])
      end

      def account_for(entry)
        id = entry["id"].to_s
        return nil if id.empty?

        Account.find_by(ig_user_id: id) || Account.find_by(page_id: id)
      end
    end
  end
end

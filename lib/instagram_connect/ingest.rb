module InstagramConnect
  # Turns a verified Meta webhook payload into persisted rows, and fires the
  # configured host callbacks (on_message / on_comment / on_postback) so the
  # host can layer notifications, AI drafting or CRM linking on top.
  #
  # Every event is banked on InstagramConnect::WebhookEvent before anything
  # parses it. That is what makes an unparsed or mis-parsed event recoverable:
  # Meta neither stores nor re-delivers webhooks, so anything dropped here is
  # gone permanently. See Ingest::Dispatcher for the walk.
  #
  # Returns a Summary, which reads like the plain hash 0.2.x returned.
  class Ingest
    def self.call(payload:, config: InstagramConnect.configuration)
      Dispatcher.new(config).call(payload)
    end
  end
end

require_relative "ingest/envelope"
require_relative "ingest/summary"
require_relative "ingest/handlers/base"
require_relative "ingest/handlers/messages"
require_relative "ingest/handlers/messaging_postbacks"
require_relative "ingest/handlers/message_reactions"
require_relative "ingest/handlers/messaging_seen"
require_relative "ingest/handlers/messaging_referral"
require_relative "ingest/handlers/messaging_optins"
require_relative "ingest/handlers/messaging_handover"
require_relative "ingest/handlers/comments"
require_relative "ingest/handlers/mentions"
require_relative "ingest/handlers/story_insights"
require_relative "ingest/handlers/unknown"
require_relative "ingest/registry"
require_relative "ingest/dispatcher"

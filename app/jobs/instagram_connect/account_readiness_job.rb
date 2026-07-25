require "httparty"

module InstagramConnect
  # Closes the gap between "an operator clicked Connect" and "events actually
  # flow", then keeps it closed.
  #
  # Two things stand in that gap and neither has a dashboard equivalent:
  #
  #   1. TOKEN GRADE. The OAuth exchange returns a long-lived *user* token, but
  #      every Instagram messaging call and the subscription below are Page
  #      token operations. This swaps in the Page token. Page tokens minted from
  #      a long-lived user token do not expire, so the expiry is cleared with it.
  #   2. PAGE SUBSCRIPTION. Ticking webhook fields in the app dashboard
  #      subscribes the *app*. Meta delivers nothing until the *Page* lists the
  #      app in its subscribed_apps, which is a per-Page Graph call.
  #
  # Both steps read before they write, so a scheduled run costs two GETs and
  # changes nothing once an account is healthy. That is the point: a token Meta
  # rotates, or a subscription dropped when an app moves between Development and
  # Live mode, heals itself rather than becoming a console command nobody
  # remembers to run.
  #
  # This lives in the gem rather than in a host because the field list has to
  # track what Ingest can actually parse. Maintained separately, the two drift
  # and the host silently receives events it drops.
  class AccountReadinessJob < ApplicationJob
    queue_as :default

    HTTP_TIMEOUT = 15

    def self.subscribed_fields
      Ingest::Registry.subscribable_fields
    end

    # Cheap negative check so an install with no connected account never
    # enqueues anything.
    def self.enqueue_if_needed
      return :nothing_to_do if InstagramConnect.configuration.app_id.blank?
      return :nothing_to_do unless connectable.exists?

      perform_later
      :enqueued
    end

    def self.connectable
      Account.active.where.not(page_id: [ nil, "" ])
    end

    def perform
      return if InstagramConnect.configuration.app_id.blank?

      self.class.connectable.find_each do |account|
        # Cleared up front rather than on success, so a step that records a soft
        # failure (no Page token, say) is not immediately wiped by the same pass
        # completing without raising.
        account.update_columns(readiness_error: nil) if account.readiness_error.present?

        ensure_page_token(account)
        ensure_subscription(account)
      rescue StandardError => e
        # One unhealthy account must not stop the rest, and the next run retries
        # anyway. The reason is kept on the row so a health screen can show it.
        account.update_columns(readiness_error: "#{e.class}: #{e.message}".truncate(255))
        logger&.error("[InstagramConnect] readiness failed for account=#{account.id}: #{e.message}")
      end
    end

    private

    def logger
      InstagramConnect.configuration.logger
    end

    # A Page token's /me is the Page itself; a user token's /me is the person.
    # That one field is the cheapest way to tell which grade we are holding.
    def ensure_page_token(account)
      return if account.page_access_token.present? && account.page_token_verified_at.present?

      identity = graph_get(account, "/me", fields: "id")

      # Already holding a Page token — which is the state a host arrives in if
      # it swapped the token itself before this job existed. /me/accounts cannot
      # be called with a Page token, so the token cannot be re-derived; adopt
      # what is there rather than attempting a recovery that cannot work.
      if identity["id"].to_s == account.page_id.to_s
        account.update!(page_access_token: account.api_token, page_token_verified_at: Time.current)
        return
      end

      pages = graph_get(account, "/me/accounts", fields: "id,access_token")
      page = Array(pages["data"]).find { |p| p["id"].to_s == account.page_id.to_s }

      if page.nil? || page["access_token"].blank?
        account.update!(needs_reconnect: true,
                        readiness_error: "no Page token for page=#{account.page_id}")
        return
      end

      account.update!(page_access_token: page["access_token"], page_token_verified_at: Time.current,
                      token_expires_at: nil, needs_reconnect: false)
    end

    def ensure_subscription(account)
      return if account.page_access_token.blank?

      wanted = self.class.subscribed_fields
      current = graph_get(account, "/#{account.page_id}/subscribed_apps", fields: "subscribed_fields")
      subscribed = Array(current["data"]).flat_map { |app| Array(app["subscribed_fields"]) }.map(&:to_s)

      if (wanted - subscribed).empty?
        account.update!(subscribed_fields: subscribed.join(","), subscriptions_synced_at: Time.current)
        return
      end

      graph_post(account, "/#{account.page_id}/subscribed_apps", subscribed_fields: wanted.join(","))
      account.update!(subscribed_fields: wanted.join(","), subscriptions_synced_at: Time.current)
    end

    def graph_get(account, path, **query)
      parse(HTTParty.get(url(account, path), headers: bearer(account), query: query,
                         timeout: HTTP_TIMEOUT), path)
    end

    def graph_post(account, path, **body)
      parse(HTTParty.post(url(account, path), headers: bearer(account), body: body,
                          timeout: HTTP_TIMEOUT), path)
    end

    # Host and version come from the account's own strategy, so this can never
    # drift onto a different Graph version than the client's calls.
    def url(account, path)
      config = InstagramConnect.configuration.for_auth_path(account.auth_path)
      "#{Auth.for(config).graph_host}/#{config.graph_version}#{path}"
    end

    def bearer(account)
      { "Authorization" => "Bearer #{account.api_token}" }
    end

    def parse(response, path)
      body = response.parsed_response
      body = {} unless body.is_a?(Hash)
      raise "Graph #{path} failed: HTTP #{response.code} #{body.dig('error', 'message')}" unless response.success?

      body
    end
  end
end

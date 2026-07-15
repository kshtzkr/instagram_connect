module InstagramConnect
  # Base controller for the engine's UI (OAuth, inbox, comments, publishing).
  # Inherits from the host's configured parent controller so it picks up the
  # host layout, auth helpers, and CSRF handling, then runs the configured
  # authentication hook. The webhook controller deliberately does NOT inherit
  # from this — it authenticates by HMAC, not by host session.
  class ApplicationController < InstagramConnect.configuration.parent_controller.constantize
    before_action :authenticate_instagram_connect!
    layout :instagram_connect_layout

    private

    # Use the host's application layout by default (so the inbox looks native),
    # or the engine's own bundled layout when the host opts out.
    def instagram_connect_layout
      InstagramConnect.configuration.inherit_host_layout ? "application" : "instagram_connect/application"
    end

    def authenticate_instagram_connect!
      handler = InstagramConnect.configuration.authenticate_with
      instance_exec(&handler) if handler.respond_to?(:call)
    end

    def instagram_connect_user_id
      resolver = InstagramConnect.configuration.current_user_id_resolver
      resolver.respond_to?(:call) ? instance_exec(&resolver) : nil
    end
    helper_method :instagram_connect_user_id
  end
end

module InstagramConnect
  # Drives the "Connect Instagram" OAuth flow: redirect to Meta's login dialog,
  # then exchange the returned code for a stored Account.
  class OauthController < ApplicationController
    def start
      state = SecureRandom.urlsafe_base64(16)
      session[:instagram_connect_oauth_state] = state
      url = Auth.for(InstagramConnect.configuration).authorize_url(redirect_uri: callback_url, state: state)
      redirect_to url, allow_other_host: true
    end

    def callback
      return redirect_with("Instagram authorization was declined: #{params[:error]}") if params[:error].present?
      return redirect_with("OAuth state mismatch — please try connecting again.") if invalid_state?

      Connect.call(code: params[:code], redirect_uri: callback_url, connected_by_id: instagram_connect_user_id)
      session.delete(:instagram_connect_oauth_state)
      redirect_to after_connect_path, notice: "Instagram account connected."
    rescue InstagramConnect::Error => e
      redirect_with("Could not connect Instagram: #{e.message}")
    end

    private

    def invalid_state?
      params[:state].to_s != session[:instagram_connect_oauth_state].to_s
    end

    def redirect_with(alert)
      redirect_to after_connect_path, alert: alert
    end

    # Meta enforces an exact-match redirect URI. Hosts can pin it via
    # config.redirect_uri; otherwise the engine's own callback URL is used.
    def callback_url
      InstagramConnect.configuration.redirect_uri.presence || url_for(action: :callback, only_path: false)
    end

    def after_connect_path
      InstagramConnect.configuration.after_connect_redirect
    end
  end
end

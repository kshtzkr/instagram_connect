InstagramConnect::Engine.routes.draw do
  # Meta webhook: GET verify handshake, POST event delivery.
  get "webhooks", to: "webhooks#verify"
  post "webhooks", to: "webhooks#receive"

  # OAuth connect flow.
  get "oauth/start", to: "oauth#start"
  get "oauth/callback", to: "oauth#callback"

  # DM inbox.
  resources :conversations, only: %i[index show] do
    resources :messages, only: :create
  end

  # Comment moderation.
  resources :comments, only: %i[index destroy] do
    member do
      post :reply
      post :hide
      post :unhide
    end
  end

  root to: "conversations#index"
end

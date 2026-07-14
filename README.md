# instagram_connect

A mountable Rails engine that connects your app to **Instagram** over the official
**Meta Graph API** — receive and reply to DMs and comments in real time via
HMAC-verified webhooks, publish posts, and manage OAuth tokens. No unofficial
automation, no browser bots: just the sanctioned API, so your account stays safe.

> **Status:** under active construction. The engine, configuration, and value
> objects are in place; the Graph client, webhook, models, and inbox UI land in
> subsequent releases (see the [CHANGELOG](CHANGELOG.md) and `docs/roadmap.md`).

## Why official-only

Instagram permanently bans real accounts that use reverse-engineered/private-API
automation, and appeals rarely succeed — you lose the handle, followers, and DM
history at once. This gem only ever speaks the official Graph API.

## What it does

- **DMs** — receive inbound messages in real time (webhooks) and reply with text
  and media, within Meta's 24-hour messaging window (7 days with the human-agent tag).
- **Comments** — read, reply to, hide, and delete comments on your posts; send a
  one-time private reply (comment → DM).
- **Publishing** — publish images, carousels, Reels, and Stories.
- **Two auth paths** — `:instagram_login` (no Facebook Page) or `:facebook_login`
  (linked Page + durable tokens), selected by config.

## Requirements

- Rails ≥ 7.1, Ruby ≥ 3.1
- [Turbo](https://turbo.hotwired.dev/) (real-time inbox updates)
- Active Storage (media attachments)
- An Active Job backend (Solid Queue, Sidekiq, …)
- Active Record Encryption configured for token storage (`bin/rails db:encryption:init`),
  or set `config.encrypt_tokens = false`

## Installation

```ruby
# Gemfile
gem "instagram_connect"
```

```bash
bundle install
bin/rails g instagram_connect:install   # initializer + mount + migrations (coming in a later release)
bin/rails db:migrate
```

## Configuration

```ruby
# config/initializers/instagram_connect.rb
InstagramConnect.configure do |c|
  c.auth_path    = :facebook_login              # or :instagram_login
  c.app_id       = Rails.application.credentials.dig(:instagram_connect, :app_id)
  c.app_secret   = Rails.application.credentials.dig(:instagram_connect, :app_secret)
  c.verify_token = Rails.application.credentials.dig(:instagram_connect, :verify_token)

  # Optional Rails integration hooks
  c.parent_controller = "ApplicationController"
  c.authenticate_with = ->(controller) { controller.authenticate_user! }
  c.on_message = ->(message) { NotifyOpsJob.perform_later(message.id) }
end
```

## License

Released under the [MIT License](LICENSE.txt).

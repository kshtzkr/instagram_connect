# instagram_connect

A mountable Rails engine that connects your app to **Instagram** over the official
**Meta Graph API** — receive and reply to DMs and comments in real time via
HMAC-verified webhooks, publish posts, and manage OAuth tokens. Official API only:
no reverse-engineered automation, no browser bots, so your account stays safe.

[![CI](https://github.com/kshtzkr/instagram_connect/actions/workflows/ci.yml/badge.svg)](https://github.com/kshtzkr/instagram_connect/actions/workflows/ci.yml)

## Why official-only

Instagram permanently disables real accounts that use reverse-engineered/private-API
automation, and appeals rarely succeed — you lose the handle, followers, and DM
history at once. Unlike WhatsApp (where a ban costs a replaceable phone number), an
Instagram ban costs the whole brand account. This gem only ever speaks the sanctioned
Graph API.

## Features

- **DMs** — receive inbound messages in real time (webhooks), reply with text within
  Meta's 24-hour window (extended to 7 days via the human-agent tag).
- **Comments** — read, reply to, hide/unhide, and delete comments on your posts.
- **Publishing** — publish image posts (Reels/video/carousel are on the roadmap).
- **Two auth paths** — `:instagram_login` (no Facebook Page) or `:facebook_login`
  (linked Page + durable tokens), selected by config. See
  [docs/auth_paths.md](docs/auth_paths.md).
- **Mounted inbox UI** — a ready inbox, comment moderation, and publish screens you
  can restyle to your own design system.
- **Secure by default** — encrypted tokens at rest, HMAC-verified webhooks.

## Requirements

- Rails ≥ 7.1, Ruby ≥ 3.1
- Active Storage (media attachments — roadmap) and an Active Job backend
  (Solid Queue, Sidekiq, …) for webhook ingestion + token refresh
- Active Record Encryption configured for token storage
  (`bin/rails db:encryption:init`), or set `config.encrypt_tokens = false`
- An Instagram **professional** account (Business or Creator)

## Installation

```ruby
# Gemfile
gem "instagram_connect"
```

```bash
bundle install
bin/rails g instagram_connect:install   # initializer + engine mount + migrations
bin/rails db:migrate
```

The install generator writes `config/initializers/instagram_connect.rb`, mounts the
engine at `/instagram`, and copies migrations for all five tables.

## Configuration

```ruby
# config/initializers/instagram_connect.rb
InstagramConnect.configure do |config|
  config.auth_path    = :facebook_login   # or :instagram_login
  config.app_id       = Rails.application.credentials.dig(:instagram_connect, :app_id)
  config.app_secret   = Rails.application.credentials.dig(:instagram_connect, :app_secret)
  config.verify_token = Rails.application.credentials.dig(:instagram_connect, :verify_token)
  config.graph_version = "v21.0"

  # Rails integration
  config.parent_controller = "ApplicationController"
  config.authenticate_with = -> { authenticate_user! }          # runs in controller context
  config.current_user_id_resolver = -> { current_user&.id }     # attributes replies
  config.after_connect_redirect = "/instagram"

  # Optional host hooks
  config.on_message = ->(message) { NotifyOpsJob.perform_later(message.id) }
  config.on_comment = ->(comment) { }
end
```

## Connecting an account

Send an operator to `GET /instagram/oauth/start`. They authorize with Meta and are
redirected back to `config.after_connect_redirect` with a stored, encrypted
`InstagramConnect::Account`. Schedule the refresh job daily so tokens stay fresh:

```ruby
# config/recurring.yml (Solid Queue), or your scheduler of choice
instagram_connect_token_refresh:
  class: InstagramConnect::RefreshTokensJob
  schedule: every day at 3am
```

## Webhooks

Point your Meta app's webhook at `https://<your-host>/instagram/webhooks` and use the
same `verify_token` you configured. Subscribe the fields you need: `messages`,
`messaging_postbacks`, `comments`, `mentions`. The engine verifies the
`X-Hub-Signature-256` HMAC on every delivery and ingests off the request path.

## The inbox UI

Mounted at `/instagram`: a DM inbox with a window-aware reply composer, a comment
moderation screen, and a publish screen. To restyle to your app's design system:

```bash
bin/rails g instagram_connect:views        # copies views into app/views/instagram_connect
bin/rails g instagram_connect:controllers  # (optional) copies controllers to override
```

## CLI

```bash
bundle exec instagram_connect doctor   # preflight your configuration
```

## Meta App Review

Messaging real customers requires Advanced Access, which requires **App Review** and
**Business Verification**. Until approved, you can only message accounts added as
testers on your Meta app. The full checklist — permissions per auth path, privacy
policy, screencasts, common rejection reasons — is in
[docs/app_review_guide.md](docs/app_review_guide.md).

## Constraints (Meta rules, not the gem's)

- **24-hour window**: you can only reply within 24h of the customer's last message
  (7 days with the human-agent tag). The gem enforces this and blocks illegal sends.
- **No cold DMs**: you can't message someone who never messaged you.
- **Publishing**: 100 API-published posts per rolling 24h; media must be at a public
  HTTPS URL.

## Testing

```bash
bundle exec rspec      # in-memory sqlite, WebMock-stubbed Graph API, 100% coverage
bundle exec rubocop
```

## Roadmap

See [docs/roadmap.md](docs/roadmap.md) — next up: Turbo realtime broadcasting and
Active Storage media (inbound fetch + outbound file send).

## License

Released under the [MIT License](LICENSE.txt).

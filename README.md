# instagram_connect

Instagram DMs, comments, and publishing for Rails, over the official Meta Graph API.

[![Gem Version](https://img.shields.io/gem/v/instagram_connect.svg)](https://rubygems.org/gems/instagram_connect)
[![CI](https://github.com/kshtzkr/instagram_connect/actions/workflows/ci.yml/badge.svg)](https://github.com/kshtzkr/instagram_connect/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.1-CC342D.svg)](https://www.ruby-lang.org)

`instagram_connect` is a mountable Rails engine that connects your app to an
Instagram professional account. You can receive and reply to DMs and comments in
real time through HMAC-verified webhooks, publish image posts, and manage OAuth
tokens. It speaks only the sanctioned Meta Graph API (Instagram Login or Facebook
Login) — there is no reverse-engineered automation or browser scripting involved.

That distinction matters: Instagram disables accounts that use private-API
automation, and an appeal rarely restores the handle, followers, or DM history.
Using the official API keeps the account in good standing.

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [Connecting an account](#connecting-an-account)
- [Webhooks](#webhooks)
- [Replying to DMs and the messaging window](#replying-to-dms-and-the-messaging-window)
- [Moderating comments](#moderating-comments)
- [Publishing](#publishing)
- [Using the Graph client directly](#using-the-graph-client-directly)
- [Background jobs](#background-jobs)
- [The inbox UI and theming](#the-inbox-ui-and-theming)
- [CLI](#cli)
- [Data model](#data-model)
- [Auth paths](#auth-paths)
- [Meta App Review](#meta-app-review)
- [Meta platform constraints](#meta-platform-constraints)
- [Testing](#testing)
- [Development](#development)
- [Contributing](#contributing)
- [Security](#security)
- [Versioning](#versioning)
- [License](#license)

## Features

- DMs: receive inbound messages in real time through webhooks, and reply with
  text inside Meta's 24-hour window (extended to 7 days with the human-agent tag).
- Comments: read, reply to, hide, unhide, and delete comments on your media.
- Publishing: publish image posts. Reels, video, and carousel are on the roadmap.
- Two auth paths: `:instagram_login` (no Facebook Page) or `:facebook_login`
  (linked Page and durable tokens), selected by configuration. See
  [docs/auth_paths.md](docs/auth_paths.md).
- A mounted UI: a DM inbox, comment moderation, and a publish screen, rendered in
  the engine's own layout and themeable from the initializer.
- Encrypted tokens at rest and HMAC-verified webhooks.

## Requirements

- Ruby >= 3.1
- Rails >= 7.1
- An Active Job backend (Solid Queue, Sidekiq, and so on). Webhook ingestion,
  outbound sends, and token refresh all run as jobs.
- Active Record Encryption configured (`bin/rails db:encryption:init`) for token
  storage, or set `config.encrypt_tokens = false` if your app has no encryption.
- A Meta app with an Instagram **professional** account (Business or Creator) and
  either Instagram Login or Facebook Login set up. See
  [docs/auth_paths.md](docs/auth_paths.md).

## Installation

Add the gem:

```ruby
# Gemfile
gem "instagram_connect"
```

Then install and migrate:

```bash
bundle install
bin/rails g instagram_connect:install   # writes the initializer and mounts the engine
bin/rails db:migrate                     # runs the gem's migrations in place
```

The install generator writes `config/initializers/instagram_connect.rb` and adds
`mount InstagramConnect::Engine => "/instagram"` to your routes. Migrations ship
inside the gem and run in place, so nothing is copied into your app and every
adopter gets the same schema, versioned with the gem. Configuration is the only
thing you add.

## Quick start

1. Fill in the initializer with your Meta app credentials (see
   [Configuration](#configuration)).
2. Point your Meta app's webhook at `https://<your-host>/instagram/webhooks` with
   the same `verify_token` (see [Webhooks](#webhooks)).
3. Send an operator to `GET /instagram/oauth/start` to connect the account.
4. Open `/instagram` for the inbox.

Check that the credentials are in place before you start:

```bash
bundle exec instagram_connect doctor
```

## Configuration

The initializer covers the settings most apps need:

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
  config.after_connect_redirect = "/instagram/conversations"

  # Optional host hooks
  config.on_message = ->(message) { NotifyOpsJob.perform_later(message.id) }
  config.on_comment = ->(comment) { }
end
```

Every setting, with its type, default, and environment-variable fallback, is
documented in [docs/CONFIGURATION.md](docs/CONFIGURATION.md). Secrets can come
from the environment instead of the initializer:
`INSTAGRAM_CONNECT_APP_ID`, `INSTAGRAM_CONNECT_APP_SECRET`,
`INSTAGRAM_CONNECT_VERIFY_TOKEN`, and others.

## Connecting an account

Send an operator to `GET /instagram/oauth/start`. The engine redirects them to
Meta's login dialog with a CSRF `state`, and Meta returns to
`GET /instagram/oauth/callback`. The callback exchanges the code for a
long-lived token and stores an `InstagramConnect::Account`, then redirects to
`config.after_connect_redirect`.

For the Facebook Login path the engine reads the Instagram business account
linked to the operator's Page to resolve the account identity. For the Instagram
Login path the identity comes back directly from the token exchange.

Meta enforces an exact-match redirect URI. If the engine's own callback URL does
not match what you registered, pin it with `config.redirect_uri`.

## Webhooks

Register `https://<your-host>/instagram/webhooks` as the callback URL in your
Meta app and set the verify token to match `config.verify_token`. Subscribe the
fields you need: `messages`, `messaging_postbacks`, `comments`, `mentions`. Meta
must reach the URL publicly, so use a staging host or a tunnel during
development; localhost will not receive callbacks.

Two things happen at that path:

- **Verification handshake (GET).** Meta sends `hub.mode=subscribe`, a
  `hub.verify_token`, and a `hub.challenge`. The controller confirms the token
  matches `config.verify_token` and echoes the challenge back, otherwise it
  responds `403`.
- **Event delivery (POST).** Every delivery carries an `X-Hub-Signature-256`
  header: the HMAC-SHA256 of the raw request body keyed by your `app_secret`.
  `InstagramConnect::SignatureVerifier` recomputes it and compares in constant
  time. A bad or missing signature is rejected with `401`. The webhook controller
  inherits `ActionController::Base` directly (not your host controller), so it
  bypasses session auth and CSRF and authenticates only by this HMAC.

A verified POST is acknowledged immediately and handed to
`InstagramConnect::IngestJob`, so Meta gets a fast `200`.
`InstagramConnect::Ingest` then walks the payload:

- **Messages** are deduped on Meta's message id through the
  `InstagramConnect::InboundMessage` ledger (so a redelivery is not processed
  twice), stored as `Message` rows on the right `Conversation`, and inbound
  messages fire `config.on_message`. Echoes of your own outbound sends are
  stored as outbound but do not fire the hook.
- **Comments** are upserted by comment id into `Comment` and fire
  `config.on_comment`.
- **Postbacks** fire `config.on_postback` with
  `{ account_id:, sender_id:, payload:, title: }`.

The engine also adds `access_token`, `app_secret`, `verify_token`, and
`hub_verify_token` to Rails' filtered parameters, so they do not appear in logs.

## Replying to DMs and the messaging window

The inbox composer creates an outbound `Message` in the `pending` state and
enqueues `InstagramConnect::SendMessageJob`. The job claims the row with an
atomic update (so a duplicate enqueue cannot double-send) and then checks Meta's
messaging window before it sends.

`InstagramConnect::MessagingWindow` encodes the rule. Measuring from the user's
last inbound message:

- within 24 hours: `:standard`, sent with no tag.
- 24 hours to 7 days: `:human_agent`, sent with the `HUMAN_AGENT` tag (human
  replies only).
- past 7 days, or the user has never messaged: `:closed`, nothing may be sent.

When the window is closed the job marks the message `failed` with reason
`outside_messaging_window` rather than calling the API. You can check the state
yourself:

```ruby
window = InstagramConnect::MessagingWindow.new(last_inbound_at: conversation.last_inbound_at)
window.open?      # => true / false
window.state      # => :standard, :human_agent, or :closed
window.send_tag   # => nil, "HUMAN_AGENT", or :blocked
```

## Moderating comments

The mounted `/instagram/comments` screen lists recorded comments and moderates
them. Moderation calls the Graph API synchronously and updates local state only
on success. The same operations are available on the client:

```ruby
client = InstagramConnect::Client.new(access_token: account.access_token, ig_user_id: account.ig_user_id)
client.reply_comment(comment_id: id, text: "Thanks!")
client.hide_comment(comment_id: id, hidden: true)
client.delete_comment(comment_id: id)
client.list_comments(media_id: media_id)
```

## Publishing

Publishing an image is a two-step Graph flow: create a media container from a
public HTTPS image URL, then publish it. The mounted `/instagram/posts` screen
does this, and the client exposes each step:

```ruby
client = InstagramConnect::Client.new(access_token: account.access_token, ig_user_id: account.ig_user_id)

container = client.create_media_container(image_url: "https://example.com/photo.jpg", caption: "Hello")
published = client.publish_media(creation_id: container.id) if container.success?

client.publishing_limit   # remaining quota in the rolling 24-hour window
```

## Using the Graph client directly

`InstagramConnect::Client` is a thin wrapper over the Graph API, bound to one
account's access token. Every call returns an `InstagramConnect::Result` rather
than raising on an API error, so callers branch on `success?`:

```ruby
client = InstagramConnect::Client.new(access_token: account.access_token, ig_user_id: account.ig_user_id)

result = client.send_text(recipient_id: igsid, text: "Hi there")
if result.success?
  result.id            # Meta's message id
else
  result.error_message # human-readable message from Meta
  result.error_code    # Meta's application-level code
  result.retry_after   # rate-limit hint, when present
end
```

Other client methods include `send_media`, `send_reaction`, `private_reply`,
`list_media`, `media_insights`, `profile`, and `list_pages`. Transport and
programming errors still raise; only API-level failures come back as a failed
`Result`.

## Background jobs

Three jobs do the asynchronous work. All use Active Job, so they run on whatever
backend your app configures.

- `InstagramConnect::IngestJob` — persists a verified webhook payload off the
  request path.
- `InstagramConnect::SendMessageJob` — sends one pending outbound message exactly
  once, enforcing the messaging window.
- `InstagramConnect::RefreshTokensJob` — refreshes tokens for active accounts
  before they expire. One account's failure does not abort the batch, and
  accounts on the Facebook Login path (non-expiring tokens) are a no-op. Schedule
  it daily:

  ```yaml
  # config/recurring.yml (Solid Queue), or your scheduler of choice
  instagram_connect_token_refresh:
    class: InstagramConnect::RefreshTokensJob
    schedule: every day at 3am
  ```

## The inbox UI and theming

Mounted at `/instagram`: a DM inbox with a window-aware reply composer, comment
moderation, and an image publish screen. By default the engine renders in its own
bundled layout and stylesheet (`inherit_host_layout` is `false`), like an admin
engine, so there is nothing to build in your app.

Tint the whole UI from the initializer. Any subset of theme keys is merged over
the defaults, with no CSS or view files in your app:

```ruby
config.theme = {
  primary: "#0057a8",
  font:    "Inter, system-ui, sans-serif",
  radius:  "12px"
}
```

The full list of theme keys and their defaults is in
[docs/CONFIGURATION.md](docs/CONFIGURATION.md#theme).

For deeper control, render inside your own layout with
`config.inherit_host_layout = true` and add `<%= instagram_connect_styles %>` to
your `<head>`, or copy the views and controllers into your app to override them:

```bash
bin/rails g instagram_connect:views        # copy views into app/views/instagram_connect
bin/rails g instagram_connect:controllers  # copy controllers to override the engine's
```

## CLI

The gem installs an `instagram_connect` executable with a `doctor` command that
checks the configuration:

```bash
bundle exec instagram_connect doctor
```

It reports `OK` or `MISSING` for each of: a valid `auth_path`, `app_id`,
`app_secret`, and `verify_token`.

## Data model

The engine owns these tables (all prefixed `instagram_connect_`):

- `Account` — a connected Instagram professional account, holding the encrypted
  access token and the identity the client sends as.
- `Conversation` — one DM thread between an account and an Instagram user
  (`igsid`), with a denormalized unread count and last-message summary.
- `Message` — one bubble in a thread, inbound or outbound, with direction,
  status, kind, and source.
- `InboundMessage` — a dedupe ledger keyed by Meta's message id.
- `Comment` — a comment on the account's media, with moderation state.

## Auth paths

The gem supports both of Meta's integration paths, selected by
`config.auth_path`. They differ in the Graph host, whether a Facebook Page is
required, the OAuth scopes, and token lifetime.
[docs/auth_paths.md](docs/auth_paths.md) covers the trade-offs and how to add a
new path.

## Meta App Review

Messaging real customers requires Advanced Access, which requires App Review and
Business Verification. Until you are approved, you can only message accounts you
add as testers on your Meta app. The checklist — permissions per auth path,
privacy policy, screencasts, and common rejection reasons — is in
[docs/app_review_guide.md](docs/app_review_guide.md).

## Meta platform constraints

These are Meta's rules, enforced by the platform rather than the gem, but worth
knowing up front:

- 24-hour window: you can only reply within 24 hours of the customer's last
  message (7 days with the human-agent tag). The gem enforces this and blocks
  sends that would violate it.
- No cold DMs: you cannot message someone who has never messaged you.
- Publishing: a rolling limit of 100 API-published posts per 24 hours, and media
  must be served from a public HTTPS URL.

## Testing

The suite boots a small in-memory dummy Rails app that mounts the engine, runs
against SQLite in memory, and stubs the Graph API with WebMock, so no database or
network access is needed:

```bash
bundle exec rspec
bundle exec rubocop
```

Coverage is held to 100% line and branch on the gem's business-logic files.

## Development

```bash
git clone https://github.com/kshtzkr/instagram_connect.git
cd instagram_connect
bundle install
bundle exec rspec
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the branch and pull-request flow.

## Contributing

Bug reports and pull requests are welcome. Please read
[CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md). Contributions must pass CI (RSpec and
RuboCop) and keep coverage at 100%.

## Security

Report vulnerabilities privately per [SECURITY.md](SECURITY.md). Please do not
open a public issue for a security problem.

## Versioning

This project follows [Semantic Versioning](https://semver.org/). Notable changes
are recorded in [CHANGELOG.md](CHANGELOG.md), and releases are listed on the
[GitHub releases page](https://github.com/kshtzkr/instagram_connect/releases).

## License

Released under the [MIT License](LICENSE.txt).

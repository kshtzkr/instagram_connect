# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/).

## [0.2.0]

True plug-and-play: the gem now owns the data model and the UI, so a host adds
**only configuration** — no copied migrations, views, or CSS.

### Changed
- **Migrations ship in the gem** (`db/migrate`) and run in place via an appended
  migration path — the host just runs `bin/rails db:migrate`. The install
  generator no longer copies migrations. The gem owns the schema, versioned with it.
- **Self-contained, themeable UI.** The gem ships its own layout + stylesheet and
  renders in its own chrome by default (`inherit_host_layout` now defaults to
  `false`, like an admin engine). Tint it entirely from the initializer via
  `config.theme = { primary:, font:, radius:, … }` (merged over sensible defaults) —
  no CSS or views in the host app.

### Fixed
- Enable `encrypts :access_token` at runtime via an engine `to_prepare` hook, so
  access tokens are encrypted at rest in host apps. Previously the decoration only
  ran in the gem's own test suite, so a host stored tokens in plain text. Opt out
  with `config.encrypt_tokens = false`.

## [0.1.0]

Initial release. A mountable Rails engine for Instagram over the official Meta Graph API.

### Added
- Mountable `InstagramConnect::Engine` + `Railtie`, `Configuration` (with `.configure`
  / `validate!`), `Result` value object, and error hierarchy.
- Both Meta auth paths as pluggable strategies (`:instagram_login`, `:facebook_login`)
  with config-symbol dispatch.
- Graph API `Client` (DMs, comments, publishing, reads, media) returning `Result`.
- OAuth connect flow (`Connect` service) → encrypted-token `Account`; scheduled
  `RefreshTokensJob`.
- HMAC (`X-Hub-Signature-256`) webhook verification + `Ingest` (DMs incl. echoes,
  comments, postbacks) with an `InboundMessage` dedupe ledger and host hooks
  (`on_message` / `on_comment` / `on_postback`).
- `MessagingWindow` (24h standard / 7d human-agent / closed) and an at-most-once
  `SendMessageJob` that enforces it.
- Mounted inbox UI: DM inbox + window-aware composer, comment moderation, image
  publishing; engine layout + overridable views.
- Generators: `install` (initializer + engine mount + migrations), `views`,
  `controllers`.
- `instagram_connect doctor` CLI + configuration preflight.
- RSpec suite (in-memory sqlite, WebMock-stubbed Graph API, mounted-engine request
  specs) at 100% line + branch coverage; `rubocop-rails-omakase`; CI on Ruby 3.2–3.4.

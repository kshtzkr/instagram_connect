# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.3.3] - 2026-07-26

### Fixed

- **Conversation sync imported nothing on the Facebook-Login path.** The conversations edge belongs
  to the PAGE, not the Instagram user — `/{ig-user-id}/conversations` answers with a capability
  error even when holding a valid Page token. The sync now targets the Page and falls back to the
  Instagram user id only when there is no Page (the Instagram-Login path). Found in production,
  where the job "succeeded" in 600ms twice while importing zero threads.
- **That failure was silent.** The job returned quietly when the listing call failed, so nothing —
  logs, health, operator — ever learned why. It now logs the account, the node it asked, and Meta's
  own error message.


## [0.3.2] - 2026-07-26

### Added

- **Existing conversations are now imported.** The gem only ever created threads from inbound
  webhooks, and webhooks only announce NEW activity — so a freshly connected account showed an
  empty inbox beside an Instagram account full of conversations, and stayed empty until somebody
  happened to message in. `SyncConversationsJob` pulls every thread and the 20 most recent messages
  in each, which is the whole history Meta exposes to any app. It runs on connect and is safe to
  re-run: threads are located by igsid and messages dedupe on `ig_message_id`.
- `Client#list_conversations` and `Client#conversation_messages`.

### Note

The Conversations API is a **Page-token** operation. An account still holding the OAuth user token
gets `(#3) Application does not have the capability to make this API call` — verified against a live
account. `AccountReadinessJob` performs that swap, so it must have run before a sync can succeed.


## [0.3.1] - 2026-07-26

### Fixed

- **Connecting an account failed when the Page came from the Login-for-Business asset picker.**
  `/me/accounts` lists only the Pages a token may *enumerate*. A Page granted through the picker is
  absent from that listing while reading perfectly well by id, so the list came back empty and the
  connect was refused — on an account that was correctly linked and fully granted. Identity
  resolution now falls back to the assets the token actually carries (`/debug_token` granular
  scopes, which needs no permission beyond the app's own credentials) and reads those Pages by id.
- **A failed Graph call was reported as a missing account.** `resolve_identity` never checked
  `Result#success?`, so an expired token or an HTTP 400 produced the same message as an empty list.
  API failures now raise `ApiError` carrying Meta's own message.
- **The error message asserted a cause it had not verified.** It claimed no Instagram account was
  linked to a Page, which was false in exactly the case that triggered it. It now states what was
  actually checked.
- **`AccountReadinessJob` had the same flaw**, hunting for a known Page inside `/me/accounts`
  instead of reading it by id — so the Page-token swap and the webhook subscription failed for the
  same accounts, silently.


## [0.3.0] - 2026-07-26

Conversations and engagement. The gem parsed 2 of the 15 webhook fields Meta can
send on the `instagram` object; it now parses 12 and durably banks the rest.

### Added
- **Webhook event ledger.** Every event is written to
  `instagram_connect_webhook_events` verbatim before anything parses it. Meta
  neither stores webhook notifications nor re-delivers them, so a parse bug used
  to be permanent data loss and is now a re-runnable row. `ReplayEventsJob`
  re-runs banked events once a handler exists, which also means a field can be
  subscribed at Meta before the gem can parse it.
- **Handlers** for `message_reactions`, `messaging_seen`, `messaging_referral`,
  `messaging_optins`, `messaging_handover`, `mentions` and `story_insights`,
  alongside the existing messages, echoes, postbacks and comments.
- **Inbound media.** Attachments get a row each and one fetch job apiece; bytes
  are copied into the host's storage with a magic-byte MIME sniff that overrides
  the declared Content-Type. Requires Active Storage in the host, and no-ops
  without it.
- **Outbound media** via Meta's Attachment Upload API, which moves bytes over an
  authenticated POST rather than exposing a signed URL to a customer's file.
- `TextSplitter`, which splits replies over Meta's 1000-**byte** message ceiling
  rather than letting the send be rejected whole.
- Sender actions, quick replies, generic templates, private replies, ice
  breakers and the persistent menu on the client.
- **Per-account tokens.** `page_access_token` is now its own encrypted column;
  `Account#client` is the only place a client is built and pins the config to
  the account's own auth path.
- `AccountReadinessJob`, moved in from host applications. It swaps the OAuth
  user token for the Page token and subscribes the Page to the webhook fields
  the ingest registry can actually parse.
- **Cursor pagination** (`Client#collect`, `#each_page`) and **rate budgets**
  (`RateLimiter`, `instagram_connect_api_budgets`), driven by Meta's own
  `X-Business-Use-Case-Usage` header rather than by local arithmetic.
- `ProfileSyncJob`, filling the `username` and `display_name` columns that had
  existed since 0.1 with nothing ever writing them.
- `MediaItem`, `Mention`, `InsightSnapshot`, `MessageAttachment`,
  `MessageReaction`, `WebhookEvent` and `ApiBudget` models, with migrations.

### Changed
- Messages carry `sent_at`, Meta's own clock. Thread ordering used our
  `created_at`, so a webhook batch delayed by a redeploy silently reordered a
  conversation. Every `Conversation` writer is now monotonic.
- Uniqueness is scoped per account. A global unique index on `ig_message_id`
  dropped messages outright when two connected accounts messaged each other.
- An attachment arriving with no URL no longer marks the message media
  `pending`. Instagram CDN links expire and cannot be re-requested, so that left
  a loading placeholder that would never resolve.
- `Ingest.call` returns a `Summary` rather than a plain Hash. It reads as the
  old hash — `skipped` still reports duplicates plus unhandled — and adds
  `duplicates`, `unhandled`, `failed` and `callback_errors`.
- Host callbacks fire outside the handler in their own rescue. The rows are
  committed by then, so a raising hook no longer marks the event failed and
  cause it to be replayed and duplicated.

### Deprecated
- `InboundMessage`. `WebhookEvent` is the dedupe claim now: keying every event
  type on one message id is wrong once `messaging_seen` carries the mid of a
  message already claimed. Kept in step for 0.2.x hosts; removal at 1.0.

### Fixed
- Every `Client` was built from the globally configured auth path, so a host
  with accounts on both paths talked to the wrong Graph host — silently.
- `refresh_access_token!` refreshed via the global strategy rather than the
  account's own.


### Documentation
- Rewrote the README with a badge row, table of contents, a quick start, and a
  usage section per feature (webhooks and signature verification, the messaging
  window, comment moderation, publishing, the Graph client, background jobs, the
  UI and theming, and the CLI).
- Added `docs/CONFIGURATION.md`, a full reference for every `Configuration`
  setting with its type, default, and environment-variable fallback.
- Added `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), and
  `SECURITY.md`.
- Removed the duplicate `MIT-LICENSE` file, keeping `LICENSE.txt` as the single
  license, and updated the gemspec `files` list to match.

## [0.2.1]

### Fixed
- Migrations are now idempotent (`create_table` / `add_index` with `if_not_exists: true`),
  so `db:migrate` / `db:prepare` succeeds on a database that already has the tables —
  e.g. an existing deploy, or one set up via `db:schema:load`. Previously a redeploy
  could fail with `PG::DuplicateTable`.

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

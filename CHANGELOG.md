# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.3.18] - 2026-07-28

### Added

- **The comment-triggered DM (private reply) can carry quick replies.** It rides the full
  messaging endpoint, so a funnel can open with buttons — titles clipped to Meta's 20 characters.

### Fixed

- **Comment webhooks no longer arrive stamped January 1970.** Meta sends messaging-webhook
  timestamps in MILLISECONDS but comment/mention change webhooks in SECONDS; dividing everything
  by 1000 collapsed every comment's clock to the epoch — which downstream read as "older than
  Meta's 7-day reply window" and silently skipped every realtime comment automation.
  `Envelope.time_from` now decides the unit by magnitude, so no caller has to know which field a
  value came from.


## [0.3.17] - 2026-07-28

### Added

- **The comment sweep announces fresh imports.** A comment younger than 24 hours that arrives via
  `SyncCommentsJob` rather than its webhook now fires the host's `on_comment` callback — once, on
  first import only, never for enriched webhook rows or older history. A fresh comment whose
  webhook was lost (or that raced an automation rule being created) is fully actionable for 7 days
  under Meta's private-reply window, so automations now self-heal on the next sweep instead of
  silently never firing. A host callback that raises is logged and never kills the walk.


## [0.3.16] - 2026-07-28

### Fixed

- **`Account#token_readable?` can no longer raise.** With previous-keys wired for rotation, a
  value no key set opens RAISES on read (AEAD tag verification) instead of returning ciphertext —
  and the raise came from inside the guard itself, turning screens that consulted it into 500s.
  Unreadable is unreadable, however the encryption layer chooses to say it.


## [0.3.15] - 2026-07-28

### Fixed

- **A send against an unreadable token fails visibly instead of stranding the bubble.** The send
  job claims the message into "sending" before building a client; the generic token guard then
  logged and stopped, leaving the message spinning forever with no failed state, no retry button
  and no reason on screen. It now fails with `token_unreadable` and the actionable message.


## [0.3.14] - 2026-07-28

### Added

- **Outbound attachments.** `UploadAttachmentJob` uploads a message's file to Meta and records the
  reusable `attachment_upload_id`; `SendMessageJob` then sends the attachment BEFORE the words
  about it, so the customer sees the photo and then the caption in the order the operator wrote
  them. Two steps rather than one because a file Meta rejects (too large, wrong type) must fail
  the message with THAT reason rather than the send's. Size ceilings are checked before an upload
  is spent, and `attachment_delivered_at` is the resume cursor so a worker killed between the two
  halves never shows the customer the photo twice. `upload_attachment`/`send_attachment` had
  existed with zero callers since 0.1.

### Fixed

- An attachment-only message no longer posts an empty text alongside it: splitting `""` yields one
  empty part, which was sent as a message.

### Migration

- `add_column :instagram_connect_messages, :attachment_delivered_at, :datetime` (`if_not_exists`).


## [0.3.13] - 2026-07-28

### Fixed

- **An echo of a message this system sent no longer collides with it.** Every outbound send stores
  Meta's mid; the echo of that same message then arrived and the handler called `create!` on the
  same mid, so the event was banked `failed` and every replay failed again — forever
  (`PG::UniqueViolation` on `index_instagram_connect_messages_on_account_and_mid`, hourly, in
  production). The echo now ENRICHES the row it is echoing — filling only what the original write
  could not know — and never rewrites direction, status, source or body, so a CMS-sent message
  cannot be turned into one that looks sent from the phone.

- **The readiness pass was the one path still shipping an unreadable token to Meta.** It builds its
  own `Authorization` header rather than going through `Account#client`, so 0.3.12's guard never
  covered it: Meta answered "Cannot parse access token" and the failure was recorded as if the
  SUBSCRIPTION were broken. It now skips such an account with the real reason on `readiness_error`,
  and the header builder itself refuses, so any future caller in that job is covered too.


## [0.3.12] - 2026-07-27

### Fixed

- **An undecryptable access token is caught here, not by Meta.** Tokens are encrypted at rest;
  with `support_unencrypted_data` on, a decrypt that fails (rotated or missing keys) hands the
  ENVELOPE back instead of raising, and every Graph call then sent that JSON blob as the bearer
  token — Meta answered `Invalid OAuth access token - Cannot parse access token` and nothing said
  the cause was local. `Account#client` now refuses to build, stamps `readiness_error` with the
  fix ("reconnect this Instagram account"), and raises `TokenUnreadableError`, which jobs log and
  stop on rather than retrying forever. `Account#token_readable?` is public for host health screens.


## [0.3.11] - 2026-07-27

### Fixed

- **Comment import asks only for fields Instagram comments support.** `from{...}` and
  `parent_id` are Facebook-comment fields; one refused field failed the whole call with (#100)
  and zero comments imported. The upsert still uses them opportunistically when Meta sends them,
  and reply nesting derives from the replies expansion itself.
- **Long reply threads import whole.** The `replies{}` expansion is a single nested page; a
  comment whose thread ran past it silently lost the tail. When the inline page says there is
  more, the comment's replies edge is now walked in full — Instagram threads are two-level,
  so this is the entire conversation.


## [0.3.10] - 2026-07-27

### Added

- **Comment history sync.** `SyncCommentsJob` walks a post's comments edge — replies expanded,
  cursors followed — and upserts by Meta's id, so webhook-created rows are enriched, never
  duplicated. Webhooks only cover comments made after the subscription existed; this imports
  everything before. `SyncMediaJob`'s full walk now enqueues one comment walk per post that
  actually has comments. Meta stays the source of truth for hidden, both directions.


## [0.3.9] - 2026-07-27

### Added

- **Stories sync.** `SyncStoriesJob` walks the `/stories` edge and mirrors live stories as
  `media_product_type: STORY` rows. Meta lists only the stories inside their 24 hours and sends no
  expiry webhook, so the job upserts what it sees and marks nothing — expired stories keep their
  rows forever, same never-delete rule as posts.
- **Carousel slides.** `MEDIA_FIELDS` now requests `children{id,media_type,media_url,thumbnail_url}`
  and the new `children` json column stores them, so hosts can render every frame of a carousel,
  not just the cover. `media_product_type` is requested too (FEED vs REELS vs STORY).
- **`MediaItem#live_story?`** — a story lives 24 hours from posting; unknown posted_at counts as expired.
- **`MediaItem.posts` scope** — everything that belongs on a feed grid. NULL-safe: rows synced
  before `media_product_type` was requested still count as posts.
- `Client#list_stories`, and the media field lists now live on `Client`
  (`Client::MEDIA_FIELDS` / `Client::STORY_FIELDS`).

### Migration

- `add_column :instagram_connect_media, :children, :json` (`if_not_exists`).


## [0.3.8] - 2026-07-27

### Added

- **Media sync now carries engagement and the poster frame.** `like_count` and `comments_count`
  come straight off the media node (no insights permission needed for the account's own posts) and
  `thumbnail_url` is the poster for videos, whose `media_url` is a playable mp4. All three columns
  existed since 0.3.0; nothing ever asked Meta for them.


## [0.3.7] - 2026-07-27

### Added

- **`SyncMediaJob` — the gem now owns the post mirror.** Walks the account's entire media listing
  (single page by default, full history with cursors via `full: true`), upserting caption,
  permalink, type and timestamps into `MediaItem`. A host built this app-side first; per the
  boundary rule — the gem owns the Graph protocol and every Instagram row — it moves here, and the
  host's copy should be deleted on upgrade.
- **`removed_from_instagram_at` on media, with `MediaItem#removed?`.** Instagram sends no webhook
  for a deleted post; absence from the account's own **completed** listing is the only signal. A
  vanished post is stamped, never destroyed, so hosts can render it grayed and locked. A failed or
  partial walk marks nothing. The migration uses `if_not_exists` because one host added the column
  app-side before the gem owned it.
- `SyncMediaJob.enqueue_throttled(account)` for screen-triggered refreshes (10-minute throttle).


## [0.3.6] - 2026-07-26

### Fixed

- **Conversation sync refused on Pages with deep Messenger history.** Meta prices the conversations
  edge per row and answered even a 20-thread page with "Please reduce the amount of data you're
  asking for" — verified live. The listing now asks for 10 at a time, drops the `updated_time`
  field nothing ever read, and on that specific refusal retries once at the smallest useful page
  before reporting Meta's own words.


## [0.3.5] - 2026-07-26

### Fixed

- **`pages_messaging` was never requested, so the Page could never be subscribed and Meta delivered
  nothing.** The permission is checked when subscribing a Page to the app — not when calling the
  messaging endpoints — so its absence broke nothing visible and stopped every webhook:

  ```
  (#200) To subscribe to the messages field, one of these permissions is needed: pages_messaging
  ```

  `subscribed_apps` rejects the entire call on the first field it cannot authorise, so a published
  app holding a valid Page token, with every dashboard field ticked, received nothing at all.

### Upgrading

Existing accounts hold a token issued before this scope existed and **must reconnect** — a token's
scopes are fixed at issue. The host's Meta app also needs a use case that offers `pages_messaging`
("Engage with customers on Messenger from Meta"); the Instagram and Pages use cases do not.


## [0.3.4] - 2026-07-26

### Fixed

- **The Page was never subscribed, so Meta delivered nothing at all.**
  `POST /{page-id}/subscribed_apps` takes Meta's **Page** field vocabulary; the gem sent the
  **Instagram** object's names. Meta rejects the entire call — every field, not just the offender —
  on the first name it does not recognise:

      (#100) Param subscribed_fields[4] must be one of {...} - got "messaging_seen"

  So a correctly configured, published app with a valid Page token received zero webhooks. The two
  lists are now deliberately separate: `subscribed_fields` is what ingest can parse, and
  `page_subscribed_fields` translates it to Page names (`messaging_seen` → `message_reads`,
  `messaging_referral` → `messaging_referrals`, `messaging_handover` → `messaging_handovers`) and
  drops the four that exist only on the `instagram` object and are subscribed in the app dashboard
  instead (`comments`, `live_comments`, `mentions`, `story_insights`).
- **Conversation sync was rejected for asking too much.** Meta answered a 50-per-page conversations
  walk with "Please reduce the amount of data you're asking for". The default page size is now 20;
  the cursor walk makes a smaller page cost one extra round trip and nothing else.


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

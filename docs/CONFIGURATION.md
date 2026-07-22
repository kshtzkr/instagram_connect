# Configuration reference

Every setting lives on `InstagramConnect::Configuration` and is set inside the
`InstagramConnect.configure` block (usually
`config/initializers/instagram_connect.rb`):

```ruby
InstagramConnect.configure do |config|
  config.auth_path = :instagram_login
  # ...
end
```

You can also set any of these through `config.instagram_connect = { ... }` in
your Rails app configuration; the engine (and the railtie) applies each key
through the matching setter at boot.

Several secrets fall back to environment variables, so a host can configure them
entirely from the environment without editing the initializer. The `configure`
block runs `validate!`, which currently checks only that `auth_path` is one of
the known values; missing secrets are reported later, at the point of use, and
by the `doctor` CLI.

## Core

| Setting | Type | Default | Environment fallback | Purpose |
| --- | --- | --- | --- | --- |
| `auth_path` | Symbol | `:instagram_login` | `INSTAGRAM_CONNECT_AUTH_PATH` | Which Meta login path and Graph host to use. One of `:instagram_login` (graph.instagram.com, no Facebook Page) or `:facebook_login` (graph.facebook.com, linked Page). Accepts a string and coerces it to a symbol. |
| `app_id` | String | `nil` | `INSTAGRAM_CONNECT_APP_ID`, then `INSTAGRAM_APP_ID` | Your Meta app's client id. |
| `app_secret` | String | `nil` | `INSTAGRAM_CONNECT_APP_SECRET`, then `INSTAGRAM_APP_SECRET` | Your Meta app's secret. Used for the OAuth code exchange and for verifying the webhook HMAC signature. |
| `verify_token` | String | `nil` | `INSTAGRAM_CONNECT_VERIFY_TOKEN`, then `INSTAGRAM_VERIFY_TOKEN` | The token you enter in the Meta webhook dashboard. The GET verification handshake must present this value. |
| `graph_version` | String | `"v21.0"` | `INSTAGRAM_CONNECT_GRAPH_VERSION` | The Graph API version segment in request URLs. |
| `redirect_uri` | String | `nil` | `INSTAGRAM_CONNECT_REDIRECT_URI` | Pin the OAuth redirect URI. Meta requires an exact match. When blank, the engine uses its own callback URL. |

## Token storage

| Setting | Type | Default | Purpose |
| --- | --- | --- | --- |
| `encrypt_tokens` | Boolean | `true` | Encrypt `Account#access_token` at rest with Active Record Encryption. Set to `false` if your app has no encryption configured. When true, run `bin/rails db:encryption:init` once and add the generated keys to your credentials. |

## Rails integration

| Setting | Type | Default | Purpose |
| --- | --- | --- | --- |
| `parent_controller` | String | `"::ApplicationController"` | The controller the engine's UI controllers inherit from, so they pick up the host layout, auth helpers, and CSRF handling. The webhook controller does not inherit from this. |
| `authenticate_with` | Callable | `nil` | A lambda run as a `before_action` in the engine's controllers. Put your host's sign-in guard here, for example `-> { authenticate_user! }`. |
| `current_user_id_resolver` | Callable | resolves `current_user&.id` in controller context | Attributes outbound replies and connected accounts to the acting operator. Runs in controller context. |
| `inherit_host_layout` | Boolean | `false` | When `false`, the engine renders in its own bundled layout and stylesheet, like an admin engine. Set `true` to render inside your app's `application` layout, then add `<%= instagram_connect_styles %>` to your `<head>`. |
| `default_per_page` | Integer | `25` | Page size for the inbox and comment lists. |
| `after_connect_redirect` | String | `"/"` | Where the OAuth callback redirects after an account is connected. The install generator sets this to `/instagram/conversations`. |

## Event hooks

Each hook is optional and receives the persisted record (or event hash) after
the webhook payload has been ingested, so you can layer on notifications, AI
replies, and the like.

| Setting | Type | Default | Receives |
| --- | --- | --- | --- |
| `on_message` | Callable | `nil` | The `InstagramConnect::Message` created for an inbound DM (not fired for echoes of your own outbound sends). |
| `on_comment` | Callable | `nil` | The `InstagramConnect::Comment` recorded from a `comments` change. |
| `on_postback` | Callable | `nil` | A hash: `{ account_id:, sender_id:, payload:, title: }`. |

## Logging

| Setting | Type | Default | Purpose |
| --- | --- | --- | --- |
| `logger` | Logger | `Logger.new($stdout)` | Where the gem logs. The token refresh job logs per-account failures here. |

## Theme

The gem ships a complete, self-styled UI. Tint it by assigning `config.theme` a
hash of any subset of the keys below; your values are merged over the defaults
(`resolved_theme`) and emitted as CSS custom properties by
`instagram_connect_styles`.

```ruby
config.theme = { primary: "#0057a8", font: "Inter, system-ui, sans-serif", radius: "12px" }
```

| Key | Default |
| --- | --- |
| `primary` | `#2563eb` |
| `primary_contrast` | `#ffffff` |
| `bg` | `#f7f8fa` |
| `surface` | `#ffffff` |
| `text` | `#111827` |
| `muted` | `#6b7280` |
| `border` | `#e5e7eb` |
| `radius` | `12px` |
| `font` | `Inter, system-ui, -apple-system, Segoe UI, Roboto, sans-serif` |
| `customer_bubble` | `#f1f3f5` |
| `staff_bubble` | `#eef2ff` |
| `ok` | `#16a34a` |
| `warn` | `#d97706` |
| `err` | `#dc2626` |

## Media

These are defined on the configuration object with the defaults below. They are
reserved for the inbound and outbound media handling on the roadmap and are not
yet read by the shipped code.

| Setting | Type | Default |
| --- | --- | --- |
| `media_max_bytes` | Integer | `26214400` (25 MB) |
| `allowed_media_types` | Array | `image/jpeg`, `image/png`, `image/gif`, `image/webp`, `video/mp4`, `audio/mpeg`, `audio/aac`, `application/pdf` |

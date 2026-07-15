# Auth paths

`instagram_connect` supports both of Meta's Instagram integration paths. Pick one via
`config.auth_path`. They differ in the Graph host, whether a Facebook Page is required,
the scope names, and the token lifetime.

## `:instagram_login` — Instagram API with Instagram Login

- **Host:** `graph.instagram.com`
- **Facebook Page:** not required — the operator logs in with Instagram credentials.
- **Scopes:** `instagram_business_basic`, `instagram_business_manage_messages`,
  `instagram_business_manage_comments`, `instagram_business_content_publish`.
- **Tokens:** a 60-day long-lived token, refreshable (the `RefreshTokensJob` handles
  this — run it daily).
- **Use when:** you're a single business connecting your own account, or you want the
  lightest setup. This is Meta's recommended path for new integrations.

## `:facebook_login` — Instagram API with Facebook Login

- **Host:** `graph.facebook.com`
- **Facebook Page:** required — the Instagram professional account must be linked to a
  Facebook Page inside Meta Business Manager.
- **Scopes:** `instagram_basic`, `instagram_manage_messages`,
  `instagram_manage_comments`, `instagram_content_publish`, `pages_show_list`,
  `pages_manage_metadata`, `pages_read_engagement`.
- **Tokens:** long-lived Page / Business-Manager System-User tokens, effectively
  non-expiring (the refresh job treats them as a no-op).
- **Use when:** your account is already managed through a Facebook Page + Business
  Manager, or you want the most durable server-to-server token story.

## Switching

Change `config.auth_path` and re-run the OAuth connect flow
(`GET /instagram/oauth/start`). Existing `Account` rows store the path they were
connected with. An app uses one path at a time.

## Adding a new path

Strategies are plain objects registered in `InstagramConnect::Auth::STRATEGIES` — the
same config-symbol dispatch used across the house gems. Implement `graph_host`,
`scopes`, `authorize_url`, `exchange_code`, and `refresh_token` on a subclass of
`InstagramConnect::Auth::Strategy` and add it to the registry.

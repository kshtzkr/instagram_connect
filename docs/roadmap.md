# Roadmap

## v0.1 (current)

- Both auth paths (Instagram Login / Facebook Login) via pluggable strategies
- Graph client (DMs, comments, publishing, reads, media) returning `Result`
- OAuth connect + encrypted-token accounts + scheduled token refresh
- HMAC-verified webhook + ingest (DMs incl. echoes, comments, postbacks) with dedupe
- Messaging-window enforcement (24h / 7d human-agent) + at-most-once send job
- Mounted inbox UI: DM inbox + composer, comment moderation, image publishing
- Generators (`install`, `views`, `controllers`) + `doctor` CLI
- 100% line + branch coverage on business logic

## v0.2 (next)

- **Turbo realtime broadcasting** — inbox rows and message bubbles update live via
  Turbo Streams from model callbacks (no polling).
- **Active Storage media** — inbound media fetch + attach (MIME sniff + size checks),
  and outbound file send via a signed, TTL'd blob URL that Meta fetches.

## Later

- Reels / video / carousel / story publishing (container status polling).
- Story mentions and replies (they arrive as DM events).
- Multiple connected accounts per host with per-account auth paths.
- Keyset pagination for high-volume inboxes.
- Optional AI reply drafting hook.

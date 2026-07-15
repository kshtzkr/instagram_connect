# Meta App Review checklist

To message real Instagram users (anyone without a role on your Meta app) you need
**Advanced Access**, which requires **App Review** *and* **Business Verification**.
Until then, development/standard access lets you message only accounts you add as
app roles/testers (~25). Budget weeks — the queue is slow and each rejection adds days.

## Permissions to request

**Instagram Login path** (`graph.instagram.com`):

- `instagram_business_basic`
- `instagram_business_manage_messages` — DMs
- `instagram_business_manage_comments` — comment moderation
- `instagram_business_content_publish` — publishing
- Human Agent — only if you need to reply beyond the 24-hour window (7-day human-agent
  replies)

**Facebook Login path** (`graph.facebook.com`):

- `instagram_basic`, `instagram_manage_messages`, `instagram_manage_comments`,
  `instagram_content_publish`
- `pages_show_list`, `pages_manage_metadata` (to subscribe the Page to webhooks),
  `pages_read_engagement`

> Scope names in the `instagram_business_*` family were finalized on 27 Jan 2025 —
> confirm the exact current strings in Meta's live Permissions Reference before you
> submit.

## Before you submit

1. **Business Verification** in Meta Business Manager (legal name, address, and a
   verifiable document / domain / phone).
2. A **public Privacy Policy URL** that clearly describes the data each requested
   permission touches.
3. App set to **Live** mode, with an app icon and category.
4. **Test credentials + step-by-step reviewer instructions.**
5. A **screencast per permission** in English, showing the real end-to-end flow
   (log in → connect the IG account → the actual DM read/send / comment / publish),
   with narration or captions.

## Common rejection reasons

- Screencasts that use dummy data, lack narration, or don't actually demonstrate the
  permission in use.
- Requesting more scopes than the demoed use case needs.
- A privacy policy that isn't publicly reachable or doesn't cover the requested data.
- No clear answer to "why does this app need this permission."
- App misconfiguration (not Live, missing test users, wrong app type).
- For messaging: missing opt-out/consent flows or inadequate webhook handling.

## Webhook subscription

Point the webhook at `https://<your-host>/instagram/webhooks`, set the verify token to
match `config.verify_token`, and subscribe: `messages`, `messaging_postbacks`,
`comments`, `mentions`. Meta must reach the URL publicly — localhost won't receive
callbacks; use a staging host or a tunnel while developing.

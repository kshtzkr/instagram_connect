# Security policy

## Supported versions

This gem is pre-1.0 and released from a single line. Security fixes land on the
latest published `0.2.x` release. Please upgrade to the newest version before
reporting, in case the issue is already fixed.

| Version | Supported          |
| ------- | ------------------ |
| 0.2.x   | :white_check_mark: |
| < 0.2   | :x:                |

## Reporting a vulnerability

Report suspected vulnerabilities privately by email to **kshtzkr@gmail.com**.
Please do not open a public GitHub issue for a security problem.

Include as much of the following as you can:

- the gem version, and your Ruby and Rails versions
- which auth path you use (`:instagram_login` or `:facebook_login`)
- a description of the issue and its impact
- steps or a proof of concept that reproduce it

You can expect an acknowledgement within a few days. Once the issue is
confirmed, a fix will be prepared and released, and the report credited if you
would like.

Do not include real secrets in a report. Access tokens, the app secret, and the
webhook verify token should be redacted or rotated rather than shared.

## Handling of secrets

A few notes on how the gem treats sensitive data, so reports can be precise:

- Access tokens are encrypted at rest with Active Record Encryption when
  `config.encrypt_tokens` is true (the default).
- The engine adds `access_token`, `app_secret`, `verify_token`, and
  `hub_verify_token` to Rails' filtered parameters, so they are redacted in
  logs.
- Inbound webhooks are authenticated by an HMAC-SHA256 signature
  (`X-Hub-Signature-256`) compared in constant time, and the verification
  handshake checks the configured `verify_token`.

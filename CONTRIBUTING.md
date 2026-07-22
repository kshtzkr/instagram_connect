# Contributing to instagram_connect

Thanks for taking the time to contribute. Bug reports, fixes, docs, and feature
work are all welcome.

## Getting set up

You need Ruby 3.1 or newer.

```bash
git clone https://github.com/kshtzkr/instagram_connect.git
cd instagram_connect
bundle install
```

The test suite boots a small in-memory dummy Rails app that mounts the engine
(see `spec/rails_helper.rb`), so there is no database to create. It runs against
SQLite in memory and stubs the Meta Graph API with WebMock, so no network access
or real credentials are needed.

## Running the checks

```bash
bundle exec rspec      # full suite
bundle exec rubocop    # style (rubocop-rails-omakase)
```

CI runs the same two commands and must pass before a pull request can merge. The
test job runs on Ruby 3.2, 3.3, and 3.4; the lint job runs on 3.3. The suite is
held to 100% line and branch coverage on the gem's business-logic files
(SimpleCov, configured in `spec/spec_helper.rb`), so new logic needs tests that
keep it there.

## Making a change

1. Branch off `main`.
2. Keep each pull request focused on one logical change.
3. Add or update specs for any behavior change, and keep coverage at 100%.
4. Run `rubocop` and `rspec` locally before pushing.
5. Update `CHANGELOG.md` under the `[Unreleased]` section.
6. Open a pull request against `main` and describe what changed and why.

## Commit style

Commits follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): short summary
```

Common types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`. The scope is
optional (for example `docs(readme):`). Keep one logical change per commit.

## Reporting bugs and requesting features

Open an issue at
https://github.com/kshtzkr/instagram_connect/issues. For bugs, include the gem
version, Ruby and Rails versions, the auth path you use
(`:instagram_login` or `:facebook_login`), and the smallest steps that
reproduce the problem.

Please do not open a public issue for security problems. See
[SECURITY.md](SECURITY.md) for private disclosure.

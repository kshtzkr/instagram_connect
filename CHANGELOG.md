# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Gem skeleton: mountable `InstagramConnect::Engine`, `Railtie`, `Configuration`
  (with `.configure` + `validate!`), `Result` value object, and error classes.
- Config surface for both Meta auth paths (`:instagram_login`, `:facebook_login`),
  secrets, Graph API version, and Rails integration hooks.

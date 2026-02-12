# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

### Added

- Elixir client for WhatsApp Web via a Deno/Baileys bridge process.
- JSON-lines stdio protocol with version envelope (`v: 1`).
- Per-call command timeouts with configurable default.
- Init handshake state machine with timeout.
- Typed event structs: `MessagesUpsert`, `MessagesUpdate`, `MessagesDelete`,
  `MessagesReaction`, `MessageReceiptUpdate`, `PresenceUpdate`.
- Data structs: `Message`, `MessageKey`, `Contact`, `Chat`, `Group`, `Presence`, `Call`.
- Consistent type coercion via `Irish.Coerce` for Baileys drift tolerance.
- Input validation: JID format, receipt types, non-empty participant lists.
- Telemetry events: `[:irish, :command, :start]`, `[:irish, :command, :stop]`,
  `[:irish, :bridge, :event]`, `[:irish, :bridge, :exit]`.
- `struct_events: false` option for raw camelCase map passthrough.
- `MessageKey.to_raw/1` for round-tripping keys back to bridge format.
- Message helpers: `text/1`, `type/1`, `media?/1`, `from/1`.
- Contact helper: `display_name/1`.
- Group operations: create, update, participants, invite, settings.
- ExDoc, Credo, Dialyxir dev tooling.
- GitHub Actions CI with Elixir/OTP matrix.

# Changelog

All notable changes to Strays are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] — 2026-07-07

First public release.

### Added

- **Live port list**, grouped by the project folder each server was launched
  from, polled every ~2s with zero-flash, in-place updates.
- **Process classification** — Vite, Next.js, webpack, Node, uvicorn, gunicorn,
  Flask, Postgres, Redis, MySQL, Docker, editors, and more, each with a glyph.
- **Exposure awareness** — teal lock for `localhost`-only, amber shield for
  `0.0.0.0`/LAN; the menu-bar icon fills in when anything is network-exposed.
- **Safe kills** — graceful SIGTERM with an honest 4-second Undo; a named
  confirmation for databases, exposed ports, and force-kills; system processes
  are protected from accidental termination.
- **Idle / forgotten detection** with one-click batch reap.
- **Free a Port** (⌘L) — find and stop whatever is holding a port.
- **CPU, memory, and live connections** per process in the inspector.
- **Menu-bar popover** with fuzzy search and quick-kill; **menu-bar-only mode**
  to hide the Dock icon.
- **AI coding sessions** (Claude Code, Copilot CLI) surfaced beside ports and
  grouped by project — model, message count, and liveness proven via a
  process-start cross-check (no phantom sessions), plus an estimated Claude cost
  from an incremental transcript tail (never a full re-read).
- **Sidebar lenses** — All · AI · All Ports · Working · Idle · Started this
  session · Exposed · Recently killed.
- **Desktop notification** when a port becomes reachable from the network.
- **Launch at login**, configurable refresh interval, and row density.

### Notes

- Native SwiftUI, macOS 14+, zero third-party dependencies. Local-only and
  read-only. Notarized; distributed via direct download and a Homebrew cask.

[Unreleased]: https://github.com/mayur-25-cd/strays/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/mayur-25-cd/strays/releases/tag/v1.0.0

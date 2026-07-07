# Contributing to Strays

Thanks for helping out! Strays is a native macOS SwiftUI app built with Swift
Package Manager — no Xcode project required.

## Getting started

```bash
git clone https://github.com/mayur-25-cd/strays.git
cd strays
swift build            # or: swift run
./scripts/build-app.sh # assembles dist/Strays.app
```

Requires Xcode 16 / Swift 6 on macOS 14+.

## Project layout

| Path | What |
| --- | --- |
| `Sources/Strays/Models` | `PortEntry`, `AISession`, and view-facing types |
| `Sources/Strays/Services` | scanning (`PortScanner`, `AISessionScanner`), classification, kill, connections |
| `Sources/Strays/State` | `PortStore` — the `@Observable` view model |
| `Sources/Strays/Views` | SwiftUI views (main window, popover, inspector, rows) |
| `scripts/` | build, icon, and notarization scripts |
| `Casks/` | the Homebrew cask |

## Adding a tool adapter (the most useful contribution)

Strays surfaces AI coding sessions by reading each tool's local files. These
formats are **undocumented and change between releases**, so adapters are
best-effort and need occasional upkeep. To add one:

1. Add a case to `AITool` in `Models/AISession.swift` (name + SF Symbol).
2. In `Services/AISessionScanner.swift`, add a parser that produces `AISession`
   values. Prove liveness by cross-checking the recorded process-start against
   the real one (see the Claude Code adapter) so a recycled PID can't fake a
   session.
3. **Privacy rule:** derive only counts/metadata. Never read, store, or transmit
   conversation contents beyond what's needed to count messages or read usage.

## Guidelines

- Match the surrounding style; keep rows sleek and push detail to the inspector.
- Semantic color only: teal = local/safe, amber = exposed, red = destructive.
- Any batch or destructive action must be behind a named confirmation.
- Run `swift build` before opening a PR. Keep changes focused.

## Reporting bugs

Open an issue with your macOS version, which tools were running, and what you
expected vs. saw. Screenshots help.

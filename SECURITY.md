# Security Policy

Strays runs entirely on your Mac. It has no network access, no telemetry, and no
backend — but it does read local files from other tools and can terminate
processes, so we take reports seriously.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report privately via GitHub: go to the **Security** tab →
**Report a vulnerability** (GitHub Private Vulnerability Reporting), or email the
maintainer listed on the GitHub profile.

Please include:

- what you found and its impact,
- steps to reproduce (a sample file or process setup helps),
- your macOS and Strays versions.

We aim to acknowledge reports within a few days and to ship a fix or mitigation
before any public disclosure.

## Scope

In scope:

- Reading maliciously-crafted local files (e.g. a crafted `~/.claude` session
  file or transcript) causing Strays to read outside its intended paths, crash,
  hang, or execute code.
- Terminating an unintended process (e.g. via PID reuse).
- Any accidental exfiltration, persistence, or logging of session-file contents.

Out of scope:

- Attacks requiring an attacker who already has write access to your home
  directory (they can already do worse than anything Strays enables).
- Gatekeeper/notarization behavior for locally-built, unsigned copies.

## Design guarantees

- **Local & read-only.** Strays never sends data off your machine. It reads
  other tools' session files only to derive counts/metadata (message counts,
  model, token usage) and never stores or transmits their contents.
- **No shell.** External tools (`lsof`, `ps`) are invoked with argument arrays,
  never through a shell.
- **Confirmed kills.** Destructive actions are gated behind confirmation and
  re-validated against the live process list before a signal is sent.

## Supported versions

The latest released version receives security fixes.

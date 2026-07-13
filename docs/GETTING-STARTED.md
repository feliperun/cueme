# Getting Started

## Prerequisites

- **macOS 26 (Tahoe)** — `SpeechAnalyzer`/`SpeechTranscriber` and the
  `Translation` framework don't exist on older SDKs.
- **Xcode 26** (Swift 6.2 toolchain).
- **Claude Code CLI**, installed and logged in — the coach/summary brain shells
  out to `claude -p`. No API key needed or used.
  ```bash
  claude --version   # prints a version if installed
  claude -p "hi"     # answers if you're logged in
  ```
  Install: https://docs.claude.com/en/docs/claude-code
- [Sentrux CLI](sentrux.md#install) for the structural quality gate.
- An **Apple Development signing identity** (free personal team is enough) —
  Xcode → Settings → Accounts → add your Apple ID, then set the CueMe target's
  Team under Signing & Capabilities once. Without a stable team, the app
  re-signs ad-hoc on every build and macOS treats it as a new app each time,
  so TCC permissions (mic, Screen Recording) never stick.

## Quick start

```bash
git clone https://github.com/feliperun/cueme.git
open cueme/CueMe.xcodeproj
# Select the CueMe scheme, ⌘R.
```

No package manager, no dependencies to install, no `.env` — the project has
zero third-party dependencies (100% native frameworks) and no secrets to
configure. First launch prompts for Microphone (required) and, if you want the
other side of the conversation, Screen & System Audio Recording (optional).

## Daily commands

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
sentrux check .           # architectural rules
sentrux gate .            # no structural regression
```

Note: this build gate is **local only** — GitHub's CI runners don't yet have the
macOS 26 SDK, so `.github/workflows/quality.yml` runs Sentrux alone. Don't skip
the local `xcodebuild` before committing; nothing else in the pipeline catches a
broken build. See [AGENTS.md § CueMe-specific gotchas](../AGENTS.md#3b-cueme-specific-gotchas-hard-won--dont-re-learn-these).

## Packaging a build

```bash
./scripts/package.sh      # Release build → dist/CueMe-<version>.dmg
```

Details on signing/notarization trade-offs: [Packaging](PACKAGING.md).

## Worktree workflow

```bash
# Create a worktree for a task (keeps main clean):
git worktree add ../CueMe-<task> -b <dev>/<issue>-<slug>
```

## Documentation map

- [Vision](VISION.md) — why this exists, current horizon
- [Architecture](ARCHITECTURE.md) — current-state structure
- [Abstractions](ABSTRACTIONS.md) — the vocabulary, layer contracts
- [ADRs](adr/README.md) — decision history (read before any structural change)
- [Sentrux](sentrux.md) — the quality gate
- [Packaging](PACKAGING.md) — building/signing/releasing a `.dmg`
- [AGENTS.md](../AGENTS.md) — the contributor/agent playbook (read this first)

## First contribution checklist

- [ ] Read [AGENTS.md](../AGENTS.md), especially the CueMe-specific gotchas.
- [ ] Confirm `claude -p "hi"` answers (brain works) before testing coach features.
- [ ] Run the local `xcodebuild` and Sentrux check suite; confirm it's green.
- [ ] `sentrux gate --save .` before touching existing files.
- [ ] Skim the [ADR index](adr/README.md) for the area you're touching.

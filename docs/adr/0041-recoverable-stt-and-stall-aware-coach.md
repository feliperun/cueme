---
type: ADR
id: "0041"
title: "Recoverable STT and stall-aware Coach delivery"
status: active
date: 2026-08-06
supersedes: "0019"
---

## Context

The reliability watchdog could replace an STT lane, but old event consumers
remained registered and Deepgram itself became permanently silent after a socket
drop. Coach failover only covered time to first token, so a provider that emitted
one fragment and then stalled retained ownership forever. Meeting trigger
cooldowns were also indistinguishable from backend failure.

## Decision

**Recover each streaming lane independently and expose deliberate waiting.**

- Deepgram reconnects with bounded exponential backoff after receive or send
  failure and retries the failed audio payload once on the replacement socket.
- Replacing an STT lane first finishes and awaits its sole prior event consumer,
  then installs exactly one replacement in `LiveAudioRouter`.
- Echo suppression requires both textual overlap and close capture timestamps.
- Coach provider output is buffered until completion; inactivity for the failover
  budget transfers ownership to the secondary without mixing partial providers.
- Meeting turns may qualify through question punctuation or sufficient context,
  the live queue retains the latest two requests, and active cooldown is visible.

All other ADR 0019 decisions remain in force, including metadata-only health,
bounded recovery budgets, durable integrity reporting and opt-in diagnostics.
This ADR replaces only its streaming recovery and failover rules.

## Options considered

- Restart the entire session: rejected because it interrupts healthy recording
  and loses warm context.
- Keep first-token ownership forever: rejected because a partial response is not
  useful guidance and blocks all recovery.
- Emit both provider streams into one card: rejected because mixed structured
  output cannot be parsed or attributed safely.

## Consequences

- Transient socket failures can recover without user intervention.
- A slow but continuously streaming Coach response is allowed to finish; a stalled
  response is replaced atomically.
- Buffering provider output trades some remote streaming immediacy for valid,
  single-provider cards; the deterministic local cue still covers initial latency.
- Users can distinguish cooldown from a broken Coach lane.

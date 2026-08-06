---
type: ADR
id: "0038"
title: "Latest Coach cue with explicit pinning"
status: active
date: 2026-08-06
supersedes: "0025"
---

## Context

ADR 0025 kept the currently visible Coach card stable until the user explicitly
advanced, dismissed or used it. In real meetings this caused newly generated
guidance to accumulate behind an older card, so the live surface repeatedly
looked stale even though the provider was producing useful results. The existing
pin action already gives users an explicit way to keep a card visible.

## Decision

**The newest useful Coach card becomes active automatically unless the currently
active card is pinned.** Pinning is the sole mechanism that freezes the visible
card while newer results continue to accumulate in the bounded history.

Empty or `NADA` results are pruned. If the active result is pruned, presentation
falls back to the newest useful, non-dismissed card instead of showing an empty
state. A speculative request consumes its matching final transcript turn only
after it has produced useful visible content; otherwise the final turn follows
the normal Coach trigger path.

All other ADR 0025 decisions remain in force, including adaptive conversation
classification, bounded history, explicit navigation and session-review
behavior. This ADR replaces only its live-card presentation rule.

## Options considered

- Keep ADR 0025's explicit-advance queue: rejected because it hides time-critical
  guidance behind stale content during a live conversation.
- Replace cards on a timer: rejected because elapsed time does not express user
  intent and competes with provider latency.
- Always replace, including pinned cards: rejected because users need a deliberate
  way to preserve a cue while speaking.

## Consequences

- Live guidance tracks the most recent actionable moment by default.
- Users can pin any card when they need it to remain visible.
- Navigation and bounded history remain available for reviewing earlier cards.
- A provider response that contains no actionable guidance cannot suppress the
  normal final-turn trigger or leave the Coach surface blank.

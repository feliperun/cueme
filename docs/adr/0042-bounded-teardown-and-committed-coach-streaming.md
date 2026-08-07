---
type: ADR
id: "0042"
title: "Bounded teardown, committed Coach streaming and backlog visibility"
status: active
date: 2026-08-07
supersedes: "0041"
---

## Context

ADR 0039 made live audio routing lossless and ADR 0041 made each streaming lane
recoverable. Both traded a bounded failure for an unbounded one, and the trades
were never closed:

- Removing the fixed teardown sleeps replaced them with unbounded awaits on
  provider and framework code. `SpeechAnalyzer` results that never end, or a
  websocket drain that never completes, hold the session in "Salvando…" forever.
- Buffering the whole primary Coach response until completion prevented mixed
  provider output, but it also stopped the card from streaming at all. Every
  card now jumps from placeholder to final, and the local latency fallback fires
  on nearly every cue.
- Retrying each failed audio payload on a fresh socket turned a network outage
  into one full backoff cycle per queued chunk, while the unbounded send queue
  grew behind it.
- The unbounded capture queue has no loss to report, so the drop counter can
  never fire. Nothing observes the queue actually growing.
- The cooldown table was duplicated between the trigger gate and the countdown
  shown in the pane, and the two copies had already diverged.

## Decision

**Every unbounded wait gets a deadline, and every unbounded queue gets a
watermark.**

- Teardown awaits — capture drain, STT `finish()`, STT event consumers, native
  results drain — run under `withDeadline`. Passing the deadline cancels the work
  and records a diagnostic; the stop sequence always completes.
- The primary Coach lane commits after its second delta and streams straight
  through from then on. A provider that emits one fragment and stalls still loses
  the race with none of its output shown, so cards stay single-provider *and*
  incremental.
- A failed Deepgram send drops that payload and schedules a reconnect instead of
  retrying inline; a failed backoff cycle opens a cooldown before the next
  attempt. The audio queue keeps draining while the socket is down.
- The capture backlog (`accepted - routed`) is sampled by the watchdog and
  reported as degraded health once it exceeds roughly four seconds of audio.
- `CoachTriggerPolicy.cooldown` is the single source of truth for pacing, read by
  both the gate and the countdown.
- The library search signature hashes the indexed fields directly instead of
  building every chunk to hash it, keeping per-keystroke cost off the archive.

All other ADR 0041 decisions remain in force. This ADR replaces only its Coach
buffering rule and its inline send-retry rule.

## Options considered

- Keep unbounded teardown awaits and fix each hang as it appears: rejected
  because the failures are in framework and provider code we do not control.
- Commit the primary on its first delta: rejected because it reinstates the
  partial-then-stall case ADR 0041 closed.
- Bound the capture queue again: rejected because dropping meeting audio is the
  original defect; growth is observable, loss is not.

## Consequences

- A wedged provider degrades the session instead of freezing the app.
- Coach cards stream again, so the latency fallback returns to being an exception.
- A network outage costs transcription for its duration but neither memory nor a
  reconnect storm.
- A consumer falling behind is visible while the meeting is still running.

---
type: ADR
id: "0045"
title: "Session diagnostics are dev telemetry"
status: active
date: 2026-08-09
---

## Context

`MemoryNote.diagnostics` held a `SessionDiagnostics` value with up to 500
individual events per note — STT turns, coach request/response pairs, provider
failovers, watchdog restarts, latency samples — persisted straight into the
user's `.md`/`session.json`. That is developer-facing runtime telemetry, not
personal memory: nothing about STT latency percentiles or which provider
served a coach request belongs in the corpus a user reads, edits, or hands to
another tool.

It also collided with the OKF corpus work in flight (`specs/okf-corpus/`):
every persisted field has to round-trip through plain Markdown, and a 500-entry
event log has no legible Markdown representation. Carrying it forward would
have meant inventing a `## Diagnostics` section nobody asked for, or silently
dropping it on the next format change — worse, doing so quietly.

## Decision

**Session diagnostics are development telemetry. They leave the durable note
and move to a rotating log outside the corpus.**

- `MemoryNote.diagnostics: SessionDiagnostics` is deleted. In its place,
  `MemoryNote.integrity: NoteIntegrity` persists exactly two counters —
  `recoveries` and `errors` — which is everything the Integrity panel ever
  showed from the raw event log.
- `DiagnosticsLog` (`CueMe/Model/DiagnosticsLog.swift`) replaces
  `AppModel.diagnostics` as the live event sink: an in-memory ring of up to 500
  events for the current session (reusing `SessionDiagnostics` internally,
  unexported) plus an append-only `diagnostics-yyyy-MM-dd.jsonl` file per day
  under `~/Library/Logs/CueMe/`, rotated by dropping files whose filename date
  is more than 7 days behind the current one.
- `DiagnosticsLog` never writes under the corpus root. It is dev-only output —
  the same category as a crash log, not a user document.
- `SessionPerformanceReport` (coach P50/P95, coverage from the request/complete
  event pair) is deleted outright along with `HistorySessionDiagnostics.swift`.
  Nothing replaces it: those numbers only existed to feed a developer-facing
  panel, and no product surface depended on them.
- `SessionIntegrityReport` (audio coverage, transcribed turns, recoveries,
  errors) stays. It now reads `record.integrity.recoveries` /
  `.errors` directly instead of scanning the event log by kind.

## Options considered

- **Keep events, cap harder, sync to disk less often.** Rejected: caps at 500
  already; the problem is never the volume, it is that the data does not
  belong in a document the user owns and edits.
- **Emit diagnostics as a Markdown section (`## Diagnostics`).** Rejected: an
  event log is not prose a user would write or want to see inline with their
  meeting notes, and it reintroduces a write-only section — the exact failure
  mode the OKF corpus work exists to remove.
- **Drop diagnostics entirely, keep nothing.** Rejected: the Integrity panel is
  a real signal (a note whose recording silently failed, or whose STT kept
  erroring, is worth flagging) — only the *raw event log* is dev-only, not the
  aggregate counters.

## Consequences

**Accepted loss:** the per-note diagnostics UI disappears (`HistorySessionDiagnostics.swift`
and its coach-latency chips are deleted, with no replacement), and the
per-note historical latency of every note saved before this change is not
recoverable — it lived only inside the now-deleted `diagnostics.events` field
and was never written anywhere else. Existing notes decode with
`integrity = NoteIntegrity()` (zero recoveries, zero errors) the first time
they are loaded after this change; a note's health story starts over from that
point forward. This is a deliberate, permanent trade: the alternative was
either keeping developer telemetry embedded in the user's own document forever
or building a migration path for numbers nobody outside the dev panel ever
looked at.

`grep -rn "SessionDiagnostics" CueMe/` now returns only two files:
`SessionDiagnostics.swift` (its own definition, still hosting `NoteIntegrity`)
and `DiagnosticsLog.swift` (its sole remaining consumer). Every other former
call site — `MemoryNote`, `AppModel`, `SessionCoordinator`, the audio-import
pipeline, `SessionReviewPane`, `SessionPerformanceReport` — now speaks either
`NoteIntegrity` (persisted) or `DiagnosticsLog` (runtime-only).

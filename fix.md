# CueMe live reliability remediation plan

> Scope: incomplete meeting recordings, silent/failed transcription, intermittent
> Coach generation, stale Coach cards, and workspace regressions that amplify live
> pipeline stalls. This document is the execution and verification ledger.

## Outcome required

- Every audio chunk accepted by capture reaches recording and the selected STT lane.
- Stopping a session drains captured audio and final transcript events deterministically.
- Streaming STT recovers from transient provider/socket failures without duplicating consumers.
- The newest useful Coach orientation is visible unless the user pins an older card.
- Empty speculative results cannot suppress normal final-turn coaching.
- Meeting coaching handles contextual questions/long turns, exposes cooldown and retains bursts.
- SwiftUI rendering and periodic archive persistence cannot block live audio routing.
- The completed Note remains file-authoritative and portable.

## Root causes confirmed

| Symptom | Root cause |
|---|---|
| Missing/silent recording intervals | Three `bufferingNewest` queues silently discarded old audio; routing inherited MainActor isolation. |
| Missing transcript tail | Session stop slept for fixed intervals, finalized STT and cancelled consumers before proving drain completion. |
| Deepgram goes permanently silent | Send/receive failures were logged but never reconnected. |
| Duplicate STT after repair | Replacement consumers were appended without awaiting/removing the previous consumer. |
| Coach always shows first card | `upsertCoach` only activated a card when no different card was already active. |
| Coach intermittently produces nothing | Empty speculative results consumed matching finals; meeting gate depended on a narrow opportunity dictionary. |
| Coach stream hangs after one token | Provider ownership became permanent after the first delta. |
| Redesign amplifies live stalls | Empty-query projection normalized the full corpus per render; live snapshots wrote JSON and Markdown synchronously on MainActor. |

## Implemented phases

### 1. Latest Coach presentation — implemented

- New useful cards become active immediately unless the current card is pinned.
- Pruning an empty active card falls back to the newest useful non-dismissed card.
- Speculative matching consumes a final only when its exact card has useful content.
- Synthetic E2E fixture contains two cards and asserts the latest one.
- ADR 0038 supersedes the stale-card behavior in ADR 0025.

### 2. Lossless off-main audio — implemented

- `LiveAudioRouter` owns the fan-out outside MainActor and routes recording/STT concurrently.
- Capture, STT input/output and transcript-bus queues are non-dropping.
- Native STT shutdown awaits finalized analyzer results instead of cancelling the tail.
- Recorder conversion failures increment health instead of disappearing.
- Stop closes capture, awaits router drain, finalizes STT, then awaits event consumers.
- Router test injects 1,000 synthetic chunks and proves all are drained.
- ADR 0039 records the pipeline contract.

### 3. Render and persistence pressure — implemented

- Empty library searches filter/sort metadata directly; no transcript normalization occurs.
- `LiveSnapshotWriter` moves periodic JSON/Markdown saves off MainActor and coalesces bursts.
- Final save flushes older live writes first, preventing stale overwrite.
- ADR 0040 records ordering and projection constraints.

### 4. STT recovery — implemented

- Deepgram reconnects with bounded exponential backoff after send/receive failure.
- A failed payload is retried once on the replacement socket.
- STT replacement awaits the prior event consumer and atomically updates the audio router.
- Echo dedup now requires lexical overlap and a capture-time distance of at most two seconds.

### 5. Meeting Coach reliability — implemented

- Context-rich long meeting turns and punctuated questions can trigger beyond keywords.
- Cooldown is visible as `coach.cooldown` instead of appearing broken.
- Live queue retains the latest two requests rather than overwriting every pending request.
- Coach failover transfers on inactivity after initial output and never mixes providers.
- ADR 0041 supersedes the first-token-only reliability contract in ADR 0019.

## Regression coverage

- `CoachPresentationPolicyTests`: newest, pinned and prune fallback behavior.
- `LiveAudioRouterTests`: lossless 1,000-chunk drain.
- `SessionCoordinatorHeuristicsTests`: temporal echo boundary.
- `SessionRuntimeTests`: contextual meeting trigger and cooldown duration.
- `FailoverCoachSessionTests`: slow-first-token and post-token stall failover.
- `CueMeMemoryE2ETests.testLiveCoachSuggestionSurvivesIntoSessionHistory`: newest live/history card.

## Release gate

All commands must pass before merge and again in CI:

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -only-testing:CueMeUITests test
sentrux check .
sentrux gate .
```

Release is complete only when the implementation PR and release-please PR are
merged, the release-assets workflow succeeds, the GitHub release contains the
signed DMG plus SHA-256 checksum, and the signed Sparkle appcast points to the
new version.

## Release result

- Released as `v1.4.0` on 2026-08-06.
- Published `CueMe-1.4.0.dmg`, `CueMe-1.4.0.dmg.sha256` and `appcast.xml`.
- The release-assets workflow verified the asset set and EdDSA-signed appcast.

---

# Follow-up review of the 1.4.0 implementation

A verification pass over the merged work found four defects introduced by the
fixes themselves and five items left incomplete. All are addressed by
[ADR 0042](docs/adr/0042-bounded-teardown-and-committed-coach-streaming.md).

## Defects introduced by the 1.4.0 fixes

1. **Coach cards stopped streaming.** `FailoverCoachSession` buffered the entire
   primary response and emitted it only after the stream ended. Since every coach
   and summary session is wrapped in a failover, no card streamed at all and the
   local latency fallback fired on nearly every cue. The primary now commits after
   its second delta and passes through from then on, which still denies a
   stalled-after-one-fragment provider any visible output.
2. **`stop()` could hang forever.** The fixed teardown sleeps were replaced by
   unbounded awaits on provider and framework code, and `NativeTranscriber.finish()`
   waited on a results stream that is not guaranteed to end. Every teardown wait
   now runs under `withDeadline`.
3. **Reconnect storm on network loss.** Each failed Deepgram send retried the
   payload through a full 4-attempt backoff, serialized behind an unbounded queue.
   A failed send now drops that payload and schedules one reconnect, guarded by a
   cooldown after a failed cycle.
4. **The drop counter could never fire.** With an unbounded capture queue,
   `yield` never reports `.dropped`, so the watchdog check was dead code. The
   backlog (`accepted - routed`) is sampled instead and reported as degraded health.

## Items that were incomplete

5. **Library projection cost.** The empty-query shortcut fixed the idle path, but
   typing in the search still re-chunked the whole archive on every keystroke.
   `MemoryChunkBuilder.contentSignature` hashes the indexed fields directly.
6. **Speculative cues still swallowed turns.** `hasContent` is true for the local
   `InstantCue` placeholder, so a confirmed turn was discarded while the model was
   still thinking — and lost entirely if the answer came back `NADA`. Only a cue
   carrying model output counts now.
7. **Duplicated cooldown table.** The gate and the countdown had already diverged.
   `CoachTriggerPolicy.cooldown` is the single source.
8. **Missing unit coverage.** `CoachPresentationPolicyTests` was listed above but
   never existed. `CoachCardNavigationTests`, `LiveSnapshotWriterTests` and
   `AsyncDeadlineTests` cover the gaps.
9. **Echo window.** Reviewed and deliberately left at 2 s: both origins share one
   provider, and widening it starts deleting the user's own speech. The existing
   boundary test stands.

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

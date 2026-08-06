---
type: ADR
id: "0039"
title: "Lossless off-main live audio routing"
status: active
date: 2026-08-06
supersedes: "0022"
---

## Context

Capture, STT and recording were connected by several `bufferingNewest` streams.
Those queues silently discarded older buffers during UI stalls, while the
timestamp-synchronized recorder padded the missing intervals with silence. The
fan-out loop also inherited `SessionCoordinator`'s MainActor isolation, coupling
durable audio progress to workspace rendering and synchronous persistence.

## Decision

**Preserve every accepted capture buffer and route it through a dedicated actor
outside the MainActor.** `LiveAudioRouter` owns the current per-speaker STT lanes
and recorder, fans each chunk out concurrently, and exposes metadata-only health.
Capture, provider input, transcript output and transcript-bus streams use
non-dropping queues; downstream pressure may increase memory temporarily but may
never silently remove meeting content. Native shutdown awaits analyzer results
after finalizing its input so the recognized tail reaches the bus.

Session shutdown closes capture first, awaits the router's complete drain, then
finalizes STT and awaits its event consumers. STT lane recovery replaces the
session in the router atomically so recording and the healthy lane continue.
Conversion failures increment recorder health instead of disappearing.

All other ADR 0022 decisions remain in force, including explicit provider
selection, Keychain-backed credentials, native fallback and the shared live
transcription contract. This ADR replaces only its buffering and routing rules.

## Options considered

- Increase the bounded queue sizes: rejected because it only changes how long a
  UI or network stall must last before data loss.
- Block realtime audio callbacks: rejected because backpressure in AVFoundation
  and ScreenCaptureKit callbacks can destabilize capture itself.
- Record directly in both callbacks: rejected because conversion and file I/O do
  not belong on realtime capture threads.

## Consequences

- Audio already accepted by CueMe is retained through temporary UI/network stalls.
- Shutdown has deterministic ordering and retains the final captured buffers.
- Long downstream outages can grow memory; watchdog metadata must surface stalled
  consumers so recovery happens before growth becomes material.
- Provider and recording work remains independent of SwiftUI rendering latency.

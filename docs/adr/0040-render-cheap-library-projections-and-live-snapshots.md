---
type: ADR
id: "0040"
title: "Render-cheap library projections and off-main live snapshots"
status: active
date: 2026-08-06
---

## Context

The note-first shell asks for its middle-column projection during SwiftUI body
evaluation. An empty search rebuilt normalized documents containing every final
transcript even though chronological filtering needs only record metadata.
Separately, periodic live snapshots encoded and wrote three archive files on the
MainActor. Both operations could stall audio routing long enough to exhaust the
old bounded capture queues.

## Decision

**Keep render-time projections metadata-only when no search query exists, and
serialize periodic live snapshots on a dedicated writer queue.** Empty-query
library results filter and sort the already loaded records directly without
normalizing note bodies or transcripts. Semantic and lexical indexes remain for
non-empty queries.

`LiveSnapshotWriter` coalesces bursts per Note and performs archive writes away
from the MainActor. Session shutdown flushes queued live writes before saving the
final authoritative record, preserving file-first ordering and preventing a
stale snapshot from overwriting the completed Note.

## Options considered

- Cache a complete `NoteListProjection` in every view: rejected because it
  duplicates observable filter state and still leaves synchronous persistence.
- Rebuild the semantic index on every render: rejected because empty queries do
  not need content ranking.
- Debounce writes with detached tasks only: rejected because unordered tasks can
  overwrite the final archive with an older snapshot.

## Consequences

- Ordinary workspace renders scale with record metadata, not corpus text size.
- Periodic archive writes no longer block UI or audio orchestration.
- The final session save may wait briefly for prior queued writes, but ordering is
  deterministic and user-owned files remain authoritative.

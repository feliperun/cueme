---
type: ADR
id: "0043"
title: "Greenfield compatibility policy for the note corpus"
status: active
date: 2026-08-08
supersedes: ["0031"]
---

## Context

ADR 0031 made a normal filesystem tree the canonical corpus and, to reach that
layout without losing anything, kept every pre-1.0 path alive alongside it: a
flat JSON session directory under `CueMe/sessions`, an on-launch relocation of
top-level session folders into `_Inbox`/Project, a duplicated `session.md`
export, and a `SessionRecord` alias for the renamed `MemoryNote` entity.

Those paths have now outlived their purpose. The layout migration is idempotent
and has run on every launch since 1.0, the alias let two vocabularies coexist
indefinitely, and `session.md` published a second copy of each Note that nothing
in the product reads back. Carrying them costs a permanent branch in the load
path, a duplicate write on every save, and a split vocabulary in 51 source files.

## Decision

**Do not preserve backward compatibility. Remove obsolete paths instead of
adding compatibility layers, fallbacks, or migrations.**

This is rule 1 of `AGENTS.md` and it applies to the on-disk corpus like anything
else. Applied here, it removes:

- `SessionStore.loadLegacy()` and the `CueMe/sessions/*.json` directory read.
- `SessionStore.migrateToWorkspace(_:projects:)` and its launch call site.
- The `session.md` compatibility mirror written next to `note.md`.
- `typealias SessionRecord = MemoryNote`; `MemoryNote` is now the only name, and
  `Model/SessionRecord.swift` is renamed `Model/MemoryNote.swift`.

What ADR 0031 established stays in force: `MemoryNote` is the durable base
entity, `note.md` and `project.md` are canonical and user-owned, `session.json`
is the lossless sidecar, folders are relative and traversal-safe, and
SQLite/FTS5/sqlite-vec remain disposable derived indexes.

## Options considered

- **Keep the legacy paths behind a version flag.** Rejected: a flag is a
  compatibility layer with extra ceremony. It postpones the deletion instead of
  making it, and every future change has to reason about both branches.
- **Deprecate over one release, then delete.** Rejected under rule 1. It buys a
  window that only matters for archives that have not been opened since 1.0 —
  and those are recoverable by hand, because the format was always plain files.
- **Keep only `session.md`.** Rejected: nothing reads it back, so it is an
  export, and an export that no one asked for is dead weight in every Note
  folder.

## Consequences

`SessionStore.loadAll()` reads exactly one location: the workspace tree. An
archive still sitting in `CueMe/sessions` as flat JSON is no longer discovered,
and pre-1.0 folders are no longer relocated on launch — they load in place,
because discovery is a recursive scan for `session.json`. Recovering an
untouched pre-1.0 archive is a manual file move, which the file-first format
makes possible without the application.

`MemoryNote` is the single vocabulary; a `SessionRecord` reference no longer
compiles. Note folders shrink by one file, and each save performs one Markdown
write instead of two.

Legacy audio locations under `CueMe/recordings/<id>` are **not** part of this
decision. `MeetingRecording` still resolves them on read and deletes them with
their Note; removing them is a separate call with its own playback impact.

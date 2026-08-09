---
type: ADR
id: "0044"
title: "YAML frontmatter via Yams"
status: active
date: 2026-08-09
---

## Context

The note corpus is moving to an OKF v0.2 bundle (ADR 0043's greenfield policy
applied to the on-disk format; see `specs/okf-corpus/spec.md`). OKF frontmatter
requires real YAML: nested mappings, sequences of mappings, and values that must
survive a byte-exact round trip. The current parser in `NoteDocument.swift`
splits each line on its first `:` — it cannot represent nesting or a list of
mappings, and it breaks on any value containing `: `. That was an acceptable
shortcut while `note.md` was a write-only report. Once `<slug>.md` becomes the
**only** durable copy of a note (`session.json` is deleted), a parser that
cannot round-trip real YAML is not a degradation — it is data loss.

## Decision

**Add [Yams](https://github.com/jpsim/Yams) as a Swift Package dependency**,
pinned with `upToNextMinorVersion` from `6.2.2` — the same pattern already used
for Sparkle in `CueMe.xcodeproj/project.pbxproj`, not `branch`, so the build is
reproducible.

Two rules govern its use, enforced by review rather than by tooling:

1. **Yams is confined to `CueMe/Model/OKF/`.** `OKFFrontmatter.swift` is the only
   file that imports it for document encode/decode; `NoteItemAttributes.swift`
   uses it for the inline `<!--cueme {…}-->` flow-mapping codec. No other
   directory imports Yams. Section splitting, marker scanning, escaping, and
   item-line shaping stay plain `String` work — Yams has no notion of Markdown
   and pulling it further in would spread a YAML dependency through code that
   is not YAML.
2. **`Yams.Node` and `Yams.Emitter` are not `Sendable`.** Yams is libyaml (C)
   under Swift 6 strict concurrency, and these types must never be stored on a
   model type or crossed over an `await`. They may only appear inside
   synchronous, non-escaping calls — parse in, typed value out, `Node` and
   `Emitter` discarded before the function returns.

This task (T002) only adds the dependency and proves it resolves and links; the
codec that uses it is a separate task (T003).

## Options considered

- **Yams (chosen).** Pure Swift Package wrapping libyaml, no other dependencies,
  actively maintained, and the de facto standard YAML library in the Swift
  ecosystem. Confining it to one directory keeps the blast radius of "a C library
  under strict concurrency" small and reviewable.
- **Hand-rolled YAML subset parser.** Rejected: OKF frontmatter uses nested
  mappings and sequences of mappings; a subset parser is exactly the kind of
  "parser incomplete → data loss" this ADR exists to avoid, and it would have to
  reinvent scalar-quoting rules Yams already gets right.
- **JSON instead of YAML for frontmatter.** Rejected: OKF v0.2 requires YAML
  frontmatter for readability in Obsidian, MkDocs, and plain `cat`, which is the
  entire point of the corpus reform (see `spec.md`, "Outcome").

## Consequences

- The app can decode and re-emit arbitrarily nested YAML mappings and sequences,
  which `NoteDocumentReader`/`NoteDocumentWriter` (T003 onward) depend on for
  byte-exact round-tripping.
- `CueMe.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
  now pins an exact Yams revision alongside Sparkle's; this file is Xcode-managed
  and updates automatically when the package graph resolves.
- `sentrux gate .` must keep passing as `CueMe/Model/OKF/` grows — Yams staying
  out of every other directory is what keeps that gate meaningful rather than a
  formality.
- Signed, notarizable `.dmg` packaging (`scripts/package.sh`) must keep working
  with a second SPM dependency embedded; validated in this task rather than
  discovered at release time, per design.md §10 risk 5.

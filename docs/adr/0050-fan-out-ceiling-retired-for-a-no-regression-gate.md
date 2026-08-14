---
type: ADR
id: "0050"
title: "Fan-out ceiling retired in favour of a no-regression gate"
status: active
date: 2026-08-09
---

## Context

`.sentrux/rules.toml` carried `no_god_files = true`, which fails any file whose
fan-out exceeds a fixed ceiling of 15. Fan-out counts the distinct things a file
reaches: types it names, functions it calls, modules it touches.

The OKF corpus refactor adds roughly a dozen files under `CueMe/Model/OKF/`, and
the rule began failing on files nobody had touched. Splitting the accused file
was the obvious remedy and was applied five times across four tasks. It does not
work, and measuring showed why.

**Splitting a file increases the fan-out of what remains.** A call between two
declarations inside one file is not an edge; extract one of them and the same
call becomes a cross-file edge that counts. Measured on
`CueMe/Model/OKF/TranscriptDocument.swift`:

| State | fan-out |
|---|---|
| single file | 16 |
| parser and header extracted into their own files | **18** |
| the three merged back into one file | 16 |
| one small date helper moved to `OKFBundle` | 17 |

So the rule, as configured, rewards larger files and punishes separated
responsibilities — the opposite of what it is named for, and the opposite of what
`AGENTS.md` asks of this codebase.

A second effect compounds it. `sentrux check` reports `1 resolved, 323
unresolved` on this project: Swift has no per-file imports, so import resolution
is structurally inapplicable and the graph falls back to matching call names
against symbols anywhere in the project. A private helper named `text`, `write`
or `notes` therefore creates edges to unrelated files. Renaming those helpers to
`itemText`, `render` and `renderNotes` dropped the god-file count from three to
one without touching a single line of structure.

The two effects together make the absolute ceiling unactionable: the only
reliable way to satisfy it is to merge files and name members generically, both
of which make the code worse.

## Decision

**Retire the absolute fan-out ceiling. Keep the no-regression gate.**

`no_god_files` is set to `false` in `.sentrux/rules.toml`. `sentrux gate`
continues to track `god_file_count` against `.sentrux/baseline.json`, so the
number of such files can never grow beyond the committed baseline. The ratchet
survives; only the fixed threshold goes.

Two practices stay in force and are the real lever:

1. **Members in `CueMe/Model/OKF/` get distinctive names.** `renderMinutes`, not
   `minutes`. `itemText`, not `text`. This is good naming on its own merits, and
   it is what actually keeps the graph honest under name-based resolution.
2. **Do not split a file to satisfy a coupling metric.** Split when a file hosts
   two unrelated responsibilities — that judgement stands on its own. The splits
   already made during this refactor (the glossary pipeline out of
   `MeetingContext`, the CLI launcher out of `ClaudeSession`, the body renderer
   out of `NoteDocumentWriter`) were all justified that way and are kept.

## Options considered

- **Retire the ceiling, keep the regression gate (chosen).** Preserves a real
  ratchet, removes a threshold this codebase has outgrown, and stops a metric
  from dictating file layout.
- **Keep splitting.** Rejected on evidence: it raises the number it is meant to
  lower, and would have forced arbitrary splits of a 96-line view and a 145-line
  store that each hold exactly one type.
- **Merge `Model/OKF/` into two or three large files.** Would pass, and is the
  perverse incentive the rule creates. Rejected: it contradicts the module
  breakdown in `specs/okf-corpus/design.md` §8 and the separation of
  responsibilities that made each of those files reviewable.
- **Raise the ceiling instead of retiring it.** Not available — the rule is a
  boolean with a hardcoded threshold, with no configuration surface.

## Consequences

- `sentrux check` no longer fails on fan-out. Coupling grade, import cycles and
  cyclomatic complexity are unchanged and still enforced.
- `sentrux gate` becomes the sole guard on god files, and the baseline is
  re-saved at the commit that lands this decision. A future change that adds a
  file over the old ceiling will still fail the gate.
- A genuinely over-coupled file can now land without the tool objecting. Review
  carries that judgement, as it already does for everything the tool does not
  measure.
- If Sentrux later gains per-file import resolution for Swift, or a configurable
  threshold, this decision is worth revisiting — supersede it rather than editing
  it.

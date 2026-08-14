---
type: ADR
id: "0046"
title: "The note corpus is an OKF v0.2 bundle"
status: active
date: 2026-08-10
supersedes: ["0031"]
---

## Context

Every note was stored twice: `session.json`, a full `Codable` dump that was the
real source of truth, and `note.md`, readable Markdown whose sections were
**write-only**. `## Ata`, `## Pendências` and `## Transcrição` were rendered on
every save and parsed back by nothing. Only nine frontmatter keys and a delimited
body survived a round trip.

Three consequences. Correcting a transcript line in Obsidian, ticking a pending
action or fixing a decision had no effect — the next autosave overwrote it.
`AGENTS.md` claims *"Files are authoritative"*, but the Markdown was a report, not
a record. And nothing outside CueMe could produce a note.

## Decision

**The corpus is a conformant [Open Knowledge Format v0.2](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
bundle, and the Markdown is the only durable copy.** `session.json` is deleted.

The format is defined by `specs/okf-corpus/design.md` and, executably, by the
golden files in `specs/okf-corpus/contracts/`, which round-trip tests compare
against byte for byte. Changing the format means changing the contract first.

### Four rules decide every field

1. **No write-only fields.** Everything emitted is parsed back. A *rendering*
   derived from a parsed field — the `# H1`, the `00:42` clock, a footnote
   definition — is allowed, because it holds no independent state.
2. **One home per field.** No field lives in two places with a precedence rule.
3. **No cosmetic transform on parsed text.** A marker tags a line's role; it
   never decorates its content. This is what makes byte-idempotence provable.
4. **`x_cueme_*` only when OKF has no honest home** — matching semantics, not
   merely shape.

### Structure

Section identity comes from an HTML marker at column 0, never from the heading
below it, so renaming or reordering headings in an external editor cannot break
parsing. A section runs from its marker to the next one or EOF. The user's own
writing needs no fence — it is whatever sits between the H1 and the first marker,
which means a hand-written note contains no machine markers at all.

Markers and frontmatter keys are English; headings and user-visible strings are
pt-BR. Identifiers are code (`AGENTS.md` §3), and the split means changing the UI
language never changes the on-disk contract.

Item identity rides a YAML flow mapping inside an HTML comment at the end of each
anchor line. Only `text`, the done-checkbox and evidence refs stay visible;
`assignee`, `due` and `confidence` live in the comment, because rendering them as
prose and parsing them back is exactly the natural-language parser this format
exists to avoid.

### Native OKF mappings, and the rejected ones

`type`, `title`, `description` (from `goal`), `tags` (from `labels`) and
`generated` map directly. `MemoryEvidence` becomes `sources[]` plus `[^id]`
footnote refs: evidence *is* per-claim provenance pointing at the capture file,
which is what `resource` means, and it de-duplicates a quote that today is stored
once per item citing it.

Recorded so they are not relitigated:

- **`titleSource` → `generated.by`** — rejected. `generated` describes the
  document; `titleSource` describes one field.
- **`SessionTakeaway.isDone` → `status`** — rejected. OKF `status` is document
  lifecycle, not item state. `isDone` is a GFM checkbox, editable anywhere.
- **`status` / `stale_after`** — not emitted. No CueMe concept backs them.
- **`usage_window`** — would duplicate `created_at`. Rule 2.
- **`verified[]`** — not emitted; no affordance produces it. It is the natural
  home for a future "I reviewed this AI summary" action.

### No schema discriminator

`okf_version` describes OKF, not CueMe's `x_cueme_*` keys, and nothing else
records a schema version. The greenfield policy (ADR 0043) forbids an in-app
migration, so **the next breaking change to `x_cueme_*` is another one-shot
script**, like the one ADR 0049 describes. This is a decision, not an oversight.

## Options considered

- **OKF v0.2 as the durable format (chosen).** Vendor-neutral, readable and
  writable by Obsidian, MkDocs, git, an LLM or `cat`, with provenance and trust
  families that fit evidence and generation honestly.
- **Keep the JSON and fix the Markdown projection.** Rejected: two copies with a
  precedence rule is the defect, not the implementation of it.
- **Keep both, JSON canonical.** Rejected for the same reason, and it leaves
  external edits meaningless.

## Consequences

- Editing a note in any editor works: the change survives a reload and reaches
  the UI.
- The JSON export is gone, replaced by "Copiar Markdown" and "Exportar
  Markdown…", so the export and the durable copy are the same bytes. This is a
  user-visible removal and belongs in the release notes.
- Partial transcript turns are no longer persisted; only final turns reach disk.
  A real, small fidelity regression.
- A stray `session.json` left in a note folder is neither read nor deleted.
- Round-trip idempotence is a testable contract with a named test, not an
  aspiration. **Supersedes ADR 0031.**

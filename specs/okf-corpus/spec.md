# Spec — the note corpus is an OKF v0.2 bundle

What we are building and why. The *how* is in [`design.md`](design.md); the
ordering is in [`tasks/`](tasks/) and [`status.yaml`](status.yaml).

## Problem

Every note is stored twice: `session.json` (a full `Codable` dump) and `note.md`
(readable Markdown). The JSON is the real source of truth. `note.md` carries a
nine-key frontmatter and then a pile of **write-only** sections — `## Ata`,
`## Pendências`, `## Transcrição`, `## Coach` and the rest are rendered on every
save and parsed back by nothing.

Three consequences:

1. **External edits do not work.** Correct a transcript line in Obsidian, tick a
   pending action, fix a decision — the next autosave overwrites all of it. Only
   `title`, `kind`, `title_source`, `project_id`, `labels`, `updated_at` and the
   delimited body survive a round trip.
2. **The repo's own rule is violated.** `AGENTS.md` says *"Files are
   authoritative… never make a database migration the only way to recover user
   content."* Today the Markdown is a report, not a record.
3. **The format is ours alone.** Nothing outside CueMe can produce a note.

Separately, the model grew entities that do not earn their keep. `KnowledgeProject`
and `KnowledgePerson` live in a JSON catalogue in Application Support; people have
no file-first home at all; a note lives *inside* its project's folder, so
reassigning a project is a directory move that invalidates any open audio URL.

## Outcome

A corpus that is a conformant **OKF v0.2** bundle — plain Markdown with YAML
frontmatter, readable and writable by Obsidian, MkDocs, git, an LLM, or `cat`.

- `<slug>.md` is the **only** durable copy of a note. `session.json` is deleted.
- Every emitted field is parsed back. Editing the file in any editor works.
- **One entity: the note.** A project is a note. A person is a note. Notes nest
  in unlimited sub-levels; dragging one into another creates the folder.
- Capture (`raw/`: transcript, audio, attachments) is separated from knowledge
  (the `.md` concept doc).
- The corpus ships its own `AGENTS.md`, so an agent pointed at the folder knows
  how to operate on it without CueMe.

## In scope

- The on-disk format: `note` documents, `raw/transcript.md`, `index.md`, `log.md`,
  the generated corpus `AGENTS.md`.
- `Yams` as a dependency, confined to `CueMe/Model/OKF/`.
- Deleting `session.json`, the JSON export, `KnowledgeProject`, `KnowledgePerson`,
  `knowledge-entities.json`, `ProjectWorkspaceStore`, `_Inbox`, `relocate`,
  `assignProject`, and `SessionDiagnostics` as a durable field.
- The note tree: load, save, move, rename, nest by drag and drop, rewrite inbound
  links.
- A one-shot Python migration from the current tree, outside the app target.

## Out of scope

Deliberately named so nobody builds them by accident:

- **INGEST / QUERY / LINT.** Recorded in ADR 0048 as the target contract and
  written into the corpus `AGENTS.md`. No code in this plan implements them.
- **A derived concept layer.** Cross-session synthesis pages are just notes when
  they arrive; the `type` vocabulary reserves `Concept`, `Synthesis`,
  `Comparison`, `Source Summary` for them. Nothing generates them here.
- **Pointing `ClaudeSession` at the corpus.** Generating the corpus `AGENTS.md`
  does *not* change the coach's isolation (ADRs 0005 / 0008). Wiring the coach to
  the corpus is a separate decision needing its own ADR.
- **Changing the semantic index.** Chunk ids all derive from domain UUIDs that
  survive the format change; `SemanticMemoryIndex.rebuild` is untouched.
- **`.caf` transcoding.** The migration reports legacy `.caf` files; converting
  them is manual.

## Glossary

| Term | Meaning |
|---|---|
| **corpus** | The user-owned folder tree. Root of the OKF bundle. |
| **note** | The single durable entity. One `<slug>.md` concept document. |
| **note folder** | The sibling `<slug>/` directory. Exists only when the note has children or `raw/`. |
| **capture** | `raw/` — transcript, audio, attachments. What was recorded. |
| **concept doc** | Any non-reserved `.md` with YAML frontmatter and a non-empty `type`. |
| **reserved name** | `index.md`, `log.md` at any level; `raw` inside a note folder; `AGENTS.md` at the root. |
| **marker** | `<!-- cueme:<name> -->` at column 0. Carries section identity; the heading below it is decoration. |
| **item attributes** | The `<!--cueme {…}-->` flow mapping at the end of an item line. Carries the stable UUID and non-visible fields. |
| **golden file** | `contracts/*.md`. The executable definition of the format; tests compare bytes against it. |
| **residual** | Body content the parser did not claim. Preserved verbatim and re-emitted. |
| **link** | An untyped relation: a path in `x_cueme_links` or a Markdown link in the body. |
| **hierarchy** | The parent/child relation. Lives in the path and nowhere else. |

## Success criteria

The refactor is done when all of these hold:

1. Saving a note writes exactly one `.md` (plus `raw/transcript.md` when a
   transcript is loaded) and no JSON.
2. `write(read(write(n))) == write(n)` for every fixture, byte for byte.
3. Editing a title, ticking an action, and moving a note in Finder or Obsidian all
   survive a reload and show up in the UI.
4. Deleting `memory.sqlite3` and reloading rebuilds search with identical results.
5. `grep -r "KnowledgeProject\|KnowledgePerson\|projectID\|personIDs\|session.json"`
   over `CueMe/` returns nothing.
6. The migration reports `RESULT: OK — 0 mismatches` against the real archive in
   `--dry-run`.

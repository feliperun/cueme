---
type: ADR
id: "0048"
title: "A navigable corpus: reserved files and target operations"
status: active
date: 2026-08-10
---

## Context

ADR 0046 made the Markdown the only durable copy, and ADR 0047 reduced the model
to one entity with hierarchy expressed by the path. Both are about what CueMe
writes. Neither says how anything *else* reads it.

An agent — or a person with a text editor — pointed at the corpus folder faces a
tree of `.md` files with no entry point, no record of what happened to it, and no
statement of what may and may not be edited. The frontmatter is self-describing
per file, but the corpus as a whole is not. Loading it whole to answer one
question is the wrong shape at any size, and it gets worse as the corpus grows.

OKF reserves `index.md` and `log.md` for exactly this, and the reference OKF wiki
template adds an `AGENTS.md` that carries the operational schema with the
content.

## Decision

**Three reserved files make the corpus navigable and self-describing, and CueMe
writes all three.**

### `index.md` — progressive discovery

One per directory that has children, listing **direct children only**, sorted by
title, each with its `description`. A reader starts at the root index, follows a
link, and reads the next index — never loading the tree to find one note.

The bundle root's index is the only one carrying `okf_version: "0.2"`; a nested
index has no frontmatter at all. Indexes are regenerated **once per batch, never
per save**, and a level whose rendered bytes are unchanged is not written. In a
corpus that lives in git, a write that changes nothing is noise, and noise is
what makes people stop reading diffs.

### `log.md` — append-only history

One file, at the root. A new entry goes into its date group, and a new day opens
a group at the top. **Existing entries are immutable and the file is never
regenerated.** Only durable structural events are recorded — created, moved,
renamed, deleted, orphan folder found, migration. Ordinary edits are not: the
file would become a keystroke journal and nobody would read it.

The test that matters is not a count of entries. It is that the previous content
is still there byte for byte.

### `AGENTS.md` — the operational schema

Written **only when absent, and never overwritten**. It states the structure,
the frontmatter conventions, the section markers, and what may and may not be
edited — most importantly that `raw/` is capture, not knowledge: a pointed
correction is legitimate, a bulk AI rewrite destroys the record of what was
actually said.

It is not part of the bundle and carries no frontmatter. Like the reference
template, it is expected to evolve with the user, so regenerating it would erase
their edits.

### INGEST, QUERY and LINT are described, not implemented

`AGENTS.md` documents three operations as a **target contract** for whoever
operates the corpus from outside — how to bring a new source in, how to answer a
question from the tree, and what to check periodically. CueMe implements none of
them today. They are written down so an external agent has a convention to
follow and so a future implementation has a specification rather than an
invention.

### The coach's isolation does not change

`ClaudeSession` still runs from an isolated empty working directory with
`disableAllHooks` (ADR 0005, ADR 0008). Writing an `AGENTS.md` into the corpus
does **not** point the coach at it, and must not be read as a step toward that.
The reason that isolation exists is unchanged: without it the CLI picks up
whatever project context surrounds it and the coach fabricates experience from
it, which has actually happened. Pointing the coach at the corpus is a separate
decision that needs its own ADR superseding 0008.

## Consequences

- `CorpusStore.writeIndexes(for:)` returns the paths it actually wrote, so
  "nothing changed" is observable rather than assumed.
- `CorpusStore.appendLog` takes the date and time zone, so the grouping is
  testable without a clock.
- The three files are refreshed on load and after each structural change, not on
  every save.
- An explicit rename now reaches `CorpusStore.rename`, which moves the document
  and rewrites inbound links. Before this, the store surface from ADR 0047 had
  no caller and a rename only relabelled the note in memory.
- `index.md`, `log.md` and `AGENTS.md` are skipped by the tree loader, so none of
  them can be mistaken for a note.

## Alternatives considered

**One index at the root listing everything.** Simpler to write, and wrong at
every size above trivial: it makes the reader load the whole tree to answer any
question, which is the cost the per-level index exists to avoid.

**Regenerate `log.md` from the notes.** It would drift from what actually
happened — a deleted note leaves no trace to regenerate from — and it would
rewrite the file on every load. Append-only is what makes the history evidence
rather than a derived view.

**Overwrite `AGENTS.md` to keep it current.** That treats the corpus as CueMe's
output. It is the user's, and the file is the place they say how their corpus
should be worked. A CueMe upgrade silently replacing it is the same failure as
a save silently replacing an external edit.

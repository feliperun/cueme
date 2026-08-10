---
type: ADR
id: "0047"
title: "One entity, hierarchy by path"
status: active
date: 2026-08-10
---

## Context

Alongside notes, the model carried two more durable entities. `KnowledgeProject`
and `KnowledgePerson` lived in `knowledge-entities.json`, a catalog outside the
Markdown corpus, and notes pointed at them through `projectID` and `personIDs`.

That arrangement paid for itself nowhere.

A person had no home on the filesystem: there was no file to open, no place to
write down what you know about them, nothing to link to. A project *had* a
folder, but the folder was the note's physical location, so reassigning a note
to another project was a `moveItem` — invalidating audio URLs already open, and
making a metadata edit a filesystem operation by accident. Neither entity could
nest: a project could not contain a project, and an "area" larger than a project
had nowhere to exist. And both were invisible to any tool but CueMe, because
`knowledge-entities.json` is not part of the corpus ADR 0046
declares authoritative.

Underneath, all three were the same shape: a title, a description, a place in a
tree, and links to other things.

## Decision

**There is one durable entity — the note — and hierarchy is the path.**

`KnowledgeProject`, `KnowledgePerson`, `KnowledgeEntityStore`,
`knowledge-entities.json`, `ProjectWorkspaceStore`, `MemoryNote.projectID`,
`MemoryNote.personIDs`, `assignProject`, `relocate` and the `_Inbox` convention
are deleted. Nothing replaces them.

A project is a note that other notes sit under. A person is a note, typically
under `pessoas/`. An area is a note. Notes nest to any depth, and where a note
sits **is** what it belongs to.

Exactly two relations survive:

- **Hierarchy** — parent and child, expressed only by the path. It is not
  mirrored in frontmatter, because dragging a folder in Finder has to work and
  two homes for one fact is how they drift apart (`design.md` rule 2).
- **Link** — `x_cueme_links`, a list of bundle-relative paths, plus ordinary
  Markdown links in the body. Untyped, as OKF specifies: the edge is directed,
  and what it means comes from the surrounding text.

"Belongs to project Acme" becomes "lives inside `acme/`". "Marina was in this
meeting" becomes a link to `pessoas/marina-souza.md` — a real file you can open
and write in.

### What this costs

A link is a path, so moving a note changes every inbound link. The rewrite in
ADR 0046's `BacklinkIndex` is what keeps them resolving, and it runs on every
move and explicit rename. A partial failure leaves mixed links — tolerable,
because OKF requires readers to tolerate a broken link, and the count of
rewritten documents is reported rather than swallowed.

Scoping a query to "everything under Acme" is now a path-prefix scan over notes
already in memory rather than an id lookup. At this corpus size that is free,
and it buys the property that an external tool computes the same scope with
`find`.

Sorting is the one thing the path does not carry: siblings order by
`startedAt`, and there is no user-defined ordering. If that is ever wanted it
needs its own decision, not a resurrected entity.

## Consequences

- `KnowledgeEntityStore.timeline` — a pure function, and the only part of the
  catalog worth keeping — survives as `KnowledgeTimeline.entries(for:)`,
  regrouped by parent instead of by project id.
- The sidebar is the corpus tree: `NoteTreeColumn` and `NoteTreeRows` draw
  containers and children, and both are the same kind of row.
- The masthead shows linked notes as chips that navigate. Written notes get no
  speaker avatars — they were never in a room — but they do show their links.
- `inbox` is where a note lands when nothing else claims it. It is an ordinary
  note: renamable, movable, and deletable. Only the default is reserved, not
  the name.
- `grep -rn "KnowledgeProject\|KnowledgePerson\|projectID\|personIDs\|_Inbox\|assignProject\|relocate" CueMe/`
  returns nothing, and stays that way.

## Alternatives considered

**Keep projects, drop only people.** Projects at least had a folder. But the
folder was the whole of what a project was, so the entity added an id, a JSON
catalog and a second way to express "is inside" — and it still could not nest.

**Type the links** (`participant`, `about`, `follows`). OKF deliberately leaves
edges untyped, and a vocabulary invented now would be wrong later without a
migration to fix it. The text around a link already says what it means.

**Mirror the parent in frontmatter** as `x_cueme_parent`. It would make scoping
an id lookup again — and would silently disagree with the path the first time
anyone moved a file outside CueMe, which is exactly the authority ADR 0046
grants the filesystem.

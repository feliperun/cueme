---
type: ADR
id: "0049"
title: "One-shot external migration to the OKF v0.2 corpus"
status: active
date: 2026-08-09
---

## Context

The OKF v0.2 corpus reform (`specs/okf-corpus/spec.md`) deletes `session.json`,
`KnowledgeProject`, `KnowledgePerson`, `knowledge-entities.json` and
`ProjectWorkspaceStore` outright — the greenfield policy (ADR 0043) forbids
adding an in-app compatibility layer to read them. Every user who has recorded
a session before this release has a Session Archive on disk in the old shape:
`session.json` per note, an optional externally-edited `note.md` whose fields
must win over the JSON (`NoteDocument.mergeCanonicalFields`), a
`knowledge-entities.json` catalogue of projects and people, and possibly
legacy audio left under `~/Library/Application Support/CueMe/recordings/<id>/`
from before recordings moved into the Note folder. Someone has to carry that
data into the new bundle, exactly once, and the app itself is not allowed to
be that someone.

The data is irreplaceable. A migration bug that silently drops a takeaway, a
transcript turn, or a user's external edit to `note.md` is a worse outcome
than doing nothing.

## Decision

**A single external Python script, `scripts/migrate-okf.py`, performs the
migration once, outside the app.** It is not imported by `CueMe/` and ships no
Swift code; it is a release artifact the user (or an operator on their
behalf) runs manually against `--dry-run` first, then for real.

Key choices:

- **PEP 723 inline metadata, run with `uv run`.** The script declares its own
  dependency (`pyyaml`) in a `# /// script` header, so `uv run
  scripts/migrate-okf.py …` reproduces the exact environment with no project
  setup. `scripts/tests/test_migrate_okf.py` carries the same header plus
  `pytest`, so `uv run scripts/tests/test_migrate_okf.py` is self-contained
  too — no `pyproject.toml`, no ambient interpreter state to get wrong.
- **PyYAML, not a hand-rolled emitter.** Getting frontmatter quoting subtly
  wrong (a bare `no` parsing as a YAML 1.1 boolean, an unquoted date
  re-parsing as a timestamp node) is exactly the kind of defect that would
  pass a casual read and corrupt data silently. A real YAML library removes
  that entire failure class.
- **`NoteDocument.mergeCanonicalFields` precedence is replicated exactly**
  (title, kind, title_source, project_id, labels, updated_at, and the
  delimited body come from `note.md` and win over `session.json`, even when
  `note.md` declares labels/body empty — the historical implementation
  overwrites unconditionally, not just when non-empty). Skipping this would
  silently revert every edit a user made outside CueMe.
- **Two independent verify checks, both mandatory, neither a vacuous `==`.**
  A re-read check parses every written `.md` back with the script's own
  reader and compares field-by-field against what was intended. A count
  reconciliation compares notes/turns/takeaways/decisions/questions/
  annotations/artifacts/topics/distinct-evidence/attachments/attachment-bytes
  across three independently-computed phases: loaded from the old archive,
  about to be written, and re-parsed from the new bundle on disk. The script
  exits non-zero the moment any of the three disagree.
- **`--source` is never written to.** The script hashes it recursively before
  and after every run and treats a mismatch as fatal. `--dest` is refused
  outright if non-empty, unless `--force` is passed, in which case a fresh,
  fully-deterministic regeneration replaces it (never a partial merge) so
  reruns are idempotent.
- **Legacy `.caf` recordings are copied, not transcoded.** Converting them is
  explicitly out of scope (`spec.md`); the report table names how many were
  found so the operator can transcode by hand if they care.

## Options considered

- **In-app migration on first launch.** Rejected outright by ADR 0043: the
  greenfield policy is specifically written to forbid this. An in-app
  migration is also a permanent branch in the load path for a transform that
  only ever needs to run once per user.
- **Ship the migration as a Swift command-line tool in the same Xcode
  project.** Rejected: it would still be code the app target builds and
  ships, blurring the "app carries no migration code" line, and it would
  need its own JSON/YAML plumbing duplicating what the Python script gets
  from `pyyaml` for free.
- **A shell script driving `jq`/`yq`.** Rejected: the frontmatter and
  attribute-comment grammars in `design.md` §3–4 are too structured (ordered
  keys, dedup, footnote refs, five body grammars) for a stream-editing
  approach to stay both correct and readable.

## Consequences

- **A user who never runs the script keeps their old archive, untouched, and
  gets an empty corpus.** The app opens `CorpusStore.rootURL`, finds nothing,
  and starts fresh — the old `Session Archive` tree sits intact next to it on
  disk, because the script never wrote to it and the app no longer reads it.
  This is a real, user-visible gap and it must be called out in the release
  notes for the version that ships this reform: running the migration script
  is a required manual step, not an automatic upgrade.
- Running `--dry-run` first is safe and costs nothing — no directory is
  created, both verify checks still run against a scratch staging tree, and
  the report shows exactly what a real run would do.
- The script is release tooling, not a supported ongoing interface: it reads
  one fixed old schema and writes one fixed new schema. The next on-disk
  format change is another one-shot script, not an extension of this one
  (`design.md` §10 risk 7 makes the same point about the app itself never
  gaining a second migration path).
- CI runs `uv run scripts/tests/test_migrate_okf.py` on every push/PR
  (`.github/workflows/quality.yml`) as an ordinary, fast, `ubuntu-latest` job,
  independent of the macOS Xcode jobs — the script has no dependency on the
  app build.

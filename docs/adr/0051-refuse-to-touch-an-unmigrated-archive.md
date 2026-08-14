---
type: ADR
id: "0051"
title: "Refuse to touch an unmigrated archive"
status: active
date: 2026-08-14
---

## Context

ADR 0046 deleted `session.json`; ADR 0049 made the move to the OKF corpus a
one-shot external script the user runs deliberately. Both assume the app meets
an archive that has already been migrated.

Auto-update breaks that assumption. Sparkle ships this build to an existing
install without the user choosing the moment, and the archive on that machine is
still in the old layout: `<note-folder>/note.md` plus `session.json`.

Pointed at such an archive, this build does something worse than fail. It
*works*: `NoteTree.discover` finds every `note.md`, loads them as notes named
`note` nested under `_Inbox/<folder>/`, and shows a plausible-looking tree. But
`session.json` is no longer read at all, so transcripts, coach cards, minutes,
takeaways and evidence are silently absent — and the first save rewrites the
note in the new layout, dropping all of it for good.

This was found by the E2E scenario for external edits, not by design review.

## Decision

**When the chosen archive still holds a pre-OKF layout, the app reads nothing
from it and writes nothing to it.**

`CorpusStore.holdsLegacyArchive()` walks the root for a `session.json` or a
`note.md` — either is conclusive, because an OKF note is `<slug>.md` *beside*
its folder, never inside it. When it finds one, `CorpusStore` goes read-only:
every `save` is refused and logged rather than silently succeeding, the history
is left empty rather than showing a mangled tree, and the reserved files
(`index.md`, `log.md`, `AGENTS.md`) are not created. The sidebar says plainly
that the archive must be migrated first.

The verdict is per root: changing `rootOverride` or calling `setRoot` clears it,
and `refreshLegacyGuard()` re-answers the question for the new corpus. Choosing
a fresh folder must not stay stuck read-only because the previous one was old.

**This is not a compatibility layer.** ADR 0043 forbids those and nothing here
reads the old format, converts it, or migrates it. It is a stop: the app
declines to operate on data it cannot fully see.

## Consequences

- A user who auto-updates before migrating gets an app that says what to do,
  with their archive untouched, instead of an app that quietly discards half of
  every note.
- The check walks the tree once per corpus open. It is stat-only and bounded by
  the number of files, not their size.
- The guard is a process-wide flag on `CorpusStore`, so the test host inherits
  whatever verdict the app reached at launch. Scoping it to the root — reset on
  every root change — is what keeps that from leaking into unit tests, and it is
  also the honest semantics.
- Once `scripts/migrate-okf.py` has run and the archive root points at the new
  corpus, the guard finds nothing and stays off.

## Alternatives considered

**Show the legacy notes read-only.** Tempting, and dishonest: what it would show
is the Markdown half, with the transcript and minutes missing and no indication
that they exist. A partial view of someone's notes is worse than none, because
it looks complete.

**Migrate automatically on launch.** Exactly what ADR 0049 rejected. An
irreversible rewrite of the user's whole corpus is not something to do while
they are opening an app, and the script's verification pass — which is what
makes the migration trustworthy — needs a destination it controls.

**Refuse to launch.** Too blunt: the user may want to point CueMe at a different
folder, which is precisely the recovery path.

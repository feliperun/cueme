---
type: ADR
id: "0037"
title: "Visible update status"
status: active
date: 2026-07-26
---

## Context

`checkForUpdates()` handed straight to Sparkle and kept no state. Whatever the
check answered — a new version, "you are current", or a transport failure — the
app itself showed nothing. That is how a 404 feed went unnoticed across three
releases (see [ADR 0035](0035-automated-release-asset-publishing.md)): the menu
item behaved identically whether updates worked or not.

Surfacing the raw failure is not an option either. Sparkle's errors embed the
appcast URL and local cache paths, and AGENTS.md forbids showing internal URLs
or paths in user-facing copy.

## Decision

- Update state is modelled as **`AppUpdateStatus`**, a Sparkle-free value type:
  `idle`, `checking`, `upToDate(currentVersion:)`, `available(version:)`,
  `failed(reason:)`. It owns its own user-facing phrasing, so the same sentence
  renders in About, the menu bar and the controls menu.
- Failures collapse into a small closed set of **reasons** (`offline`,
  `feedUnavailable`, `unknown`), each with a fixed human explanation. Updater
  errors are classified, never echoed — a unit test asserts no summary can
  contain a URL or a filesystem path.
- `UpdateStatusReporter` is the only type that sees Sparkle, translating
  `SPUUpdaterDelegate` callbacks into statuses.
- Under UI testing the updater never starts, so E2E drives the surface through
  the `CUEME_UI_TEST_UPDATE_STATUS` fixture instead of the network — keeping the
  regression deterministic and offline, per
  [ADR 0029](0029-key-feature-e2e-regression-gate.md).

## Consequences

A broken update feed is now visible in the product, not just in CI, closing the
loop that ADR 0035 opened on the release side. The status is also the manual
test instrument for auto-update: running an older build must show the newer
version by name. Adding a failure mode means adding a reason plus its sentence,
which keeps error copy reviewable in one place instead of scattered across
views.

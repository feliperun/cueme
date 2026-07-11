---
type: ADR
id: "0010"
title: "On-device translation highlighting (NaturalLanguage), tiered not bold"
status: active
date: 2026-07-11
---

## Context

The LLM translator used to bold the 2–4 most important words (`**markdown**`) so a
foreign line could be scanned fast. When translation moved on-device
([0006](0006-on-device-stt-and-translation.md)), the Apple Translation framework
returns plain text — that emphasis was lost, and uniform bold is a blunt tool
anyway (two states, one highlighted run).

## Decision

**Rebuild the emphasis on-device with `NaturalLanguage`, as a visual hierarchy
rather than bold.** A `Highlighter` tags each word with `NLTagger`
(`.lexicalClass` + `.nameType`) and styles three tiers:

- **strong** (proper noun / number / brief keyterm) → accent color, semibold, +1pt
- **content** (noun / verb / adjective / adverb) → primary color, medium
- **function** (article / preposition / pronoun / …) → secondary, regular

The eye lands on the strong tier, content sustains, function words recede. It
runs in milliseconds, on-device, with no LLM call and no latency cost. Applied to
the transcript translation and the question banner.

## Options considered

- **NLTagger tiers** (chosen): on-device, instant, faithful to the old feature,
  richer than bold (color + weight + size).
- **Re-add an LLM highlight pass**: best "importance" judgement, but reintroduces
  the latency/contention that moving translation off the LLM removed.
- **NLEmbedding importance ranking**: on-device semantic salience, heavier and
  overkill for short lines; POS + name-type is enough.
- **Keep uniform bold**: blunt; and the plain on-device output has nothing to bold.

## Consequences

- The strong (accent) tier is naturally sparse — it only fires on names, numbers,
  or brief keyterms — so it stands out without a manual cap.
- Highlight quality tracks NaturalLanguage's per-language POS accuracy.
- The dead LLM translator prompt and the markdown helper were removed.

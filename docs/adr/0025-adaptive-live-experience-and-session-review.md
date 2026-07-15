---
type: ADR
id: "0025"
title: "Adaptive live experience and durable session review"
status: active
date: 2026-07-14
supersedes: "0023"
---

## Context

Meeting modes alone are too broad to choose useful coaching behavior. A generic
meeting may become a technical review or a one-on-one, while rapid replacement
of suggestions makes even good advice hard to use. At the same time, capture
recovery is not enough if the user cannot see the health of recording, STT and
the LLM lanes. After the call, summaries need to be editable working records,
not opaque generated text.

## Decision

**Adapt coaching to the observed conversation, expose end-to-end health, keep
the live surface glanceable, and persist a structured editable review.**

- `ConversationStyleDetector` classifies recent final turns as interview,
  one-on-one, technical, sales or open meeting while keeping explicit modes as
  strong priors. The detected style augments the provider prompt.
- Automatic coaching is limited to high-confidence questions, decisions,
  ownership, risks or feedback moments. A visible card remains until the user
  uses, dismisses or navigates away from it; newer cards wait in a bounded queue
  and can be pinned.
- `LiveHealthMonitor` derives one compact status for microphone, call audio,
  recording, transcription, Coach and summary from existing runtime truth. The
  detailed popover exposes recovery actions without adding another recovery
  owner.
- The live surface keeps one coaching card and a compact transport. Notes,
  transcript, summary, model selection and manual questions remain available
  on demand rather than competing for attention.
- `MeetingReview` stores decisions, open questions and follow-up alongside
  overview, topics and takeaways. All fields are editable; provider-generated
  review and follow-up presets use the existing post-processing lane and every
  mutation rewrites JSON and Markdown.
- `SessionIntegrityReport` records audio coverage, transcript volume,
  recoveries and errors in both the review UI and Markdown archive.

## Consequences

- Coaching changes behavior without restarting capture or changing the user’s
  selected model, but heuristic classification may lag the first few turns.
- Suggestions no longer disappear before they can be read; users explicitly
  advance them and can inspect the pending count.
- Health is end-to-end and visible while capture recovery remains centralized
  in the existing watchdog/coordinator path.
- The post-meeting review is a durable, user-correctable source of truth. LLM
  output is only accepted after structured JSON parsing; the previous valid
  state survives malformed output.
- More live controls exist, but secondary controls are hidden behind compact
  popovers to keep the default surface low-noise.

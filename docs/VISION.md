# CueMe — Product Vision

> The "why", not the "how". Short and opinionated.

## Why this, why now

Live conversations in a second language — job interviews, sales calls, hard
talks — overload you: parse what was just said, translate it in your head, and
compose a strong answer, all in a few seconds. macOS 26 finally makes the pieces
native and cheap: on-device speech (`SpeechAnalyzer`), on-device translation
(`Translation`), and a local LLM brain through the Claude Code CLI — no servers,
no API keys. CueMe stitches them into a copilot that whispers "he asked X →
answer like this" while you keep your attention on the person.

## The problem

Under pressure you lose the thread: you miss the exact question, your foreign
vocabulary evaporates, and your answer comes out long and unfocused. Generic
prep doesn't help in the moment; existing tools are web apps that need audio
drivers, cloud STT, and API keys, and they dump walls of text you can't read
while talking.

## The insight

Capturing the two sides as **separate audio sources** (your mic vs. system
audio) makes "who spoke" free — no diarization. And the assistant should read
like a **friend beside you**: one line of guidance, one ready-to-say phrase,
its translation, a couple of key words. Terse beats thorough when you're live.

## Principles

- **Local-first.** On-device STT and translation; the LLM runs through the
  user's own Claude Code CLI. No third-party keys, nothing to leak.
- **Latency is a feature.** Prewarm sessions, keep translation off the LLM,
  scan in two seconds. If it's not fast, it's useless mid-sentence.
- **Truth from the brief only.** Coaching never fabricates the user's history —
  facts come from the session brief and the pasted CV, or it offers a structure
  to fill.
- **Compact and unobtrusive.** A small, always-on-top window that sits beside
  the call, not another thing to manage.

## Near-term horizon

A single-window macOS app that, in a foreign-language mock interview, shows the
interviewer's question with translation on top, an emoji-cued coach card
(guidance + phrase + vocabulary) within ~2s, a rolling summary, and a CV-aware
brief — usable on speakers without headphones.

## Non-goals (for now)

- No iOS/Windows/web port — macOS 26 only.
- No cloud STT/translation, no bundled API keys.
- No meeting recording/storage product; CueMe is an in-the-moment assistant.
- No voice diarization engine — separation is by capture origin.

## Related docs

- [Architecture](ARCHITECTURE.md) · [Abstractions](ABSTRACTIONS.md) · [ADRs](adr/README.md)

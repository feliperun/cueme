# Architecture

> Current-state summary. ADRs in [adr/](adr/README.md) hold the history and the
> *why*; this file reflects only **active** decisions. Update it in the same
> commit as any structural change.

## High-level flow

```
AVAudioEngine (mic, .self) ─────┐
                                ├─▶ AudioConverter (→16k mono PCM16) ─▶ NativeTranscriber (SpeechAnalyzer)
ScreenCaptureKit (system, .other)┘                                          │
                                                                            ▼
                                                                    TranscriptBus (actor)
                     ┌──────────────────────────┬──────────────────────┬─────────────┐
                     ▼                          ▼                      ▼             ▼
        Apple Translation (on-device)     Summary (haiku CLI)   Coaching (opus/sonnet   AppModel
        via TranslationPipe               ~30s debounce         CLI, streaming, warm)   (@Observable)
                                                                                          │
                                                                                          ▼
                                                                                     SwiftUI (compact)
```

Single Swift process. Audio callbacks stay minimal and hand buffers to the async
world via `AsyncStream`; shared state lives in actors; the UI reads an
`@Observable` `AppModel` on the main actor.

## Components

- **Audio/** — `AudioCapture` (mic via `AVAudioEngine` + system via
  `ScreenCaptureKit`, tagged by origin, echo-dedup aware), `AudioConverter`.
- **STT/** — `NativeTranscriber` (`SpeechAnalyzer`/`SpeechTranscriber`, on-device),
  `TranslationPipe` (feeds Apple `Translation` from the `.translationTask`).
- **Bus/** — `TranscriptBus` actor: fan-out `AsyncStream` + rolling window.
- **Brain/** — `ClaudeClient` (locates the `claude` CLI), `ClaudeSession`
  (a long-lived `claude -p` streaming-json process, prewarmed), `Summary` and
  `Coaching` lanes, `Prompts`.
- **Model/** — `AppModel` (state + commands), `SessionCoordinator` (wires
  capture → STT → bus → lanes → UI, echo dedup, coach triggering), `SessionBrief`,
  `Types`.
- **Views/** — compact SwiftUI: `HeaderBar`, `QuestionBanner`, `CoachingPane`,
  `TranscriptPane`, `SummaryPane`, `BriefEditor`, `Theme`, and `Highlighter`
  (on-device `NaturalLanguage` tiering of translated lines).

## Runtime & hosting

Native macOS 26 app (Apple Silicon). No backend. The LLM runs through the user's
local **Claude Code CLI** (`claude -p`), reusing their existing login — no API
key. STT and translation are on-device.

## Observability & quality

- Build gate: `xcodebuild … build` (macOS 26 SDK). See [Getting Started](GETTING-STARTED.md).
- Structural health gated by [Sentrux](sentrux.md).
- Logging via `OSLog` (`subsystem: "CueMe"`).

## Security model

- No secrets stored by the app; the CLI holds the user's Claude auth.
- STT audio never leaves the device; translation is on-device.
- Coaching/summary text is sent to Anthropic through the user's own CLI session.
  CLI sessions run from an isolated empty cwd and the coach prompt walls off any
  ambient context so no local project/CV data leaks in unintentionally.
- Permissions: Microphone (required) and Screen & System Audio Recording
  (optional, for the other party). Non-sandboxed dev build; hardened runtime on.

## Related docs

- [Vision](VISION.md) · [Abstractions](ABSTRACTIONS.md) · [ADRs](adr/README.md) · [Sentrux](sentrux.md)

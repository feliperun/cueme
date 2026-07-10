# LiveCopilot

Real-time conversation copilot for macOS — a native SwiftUI app that listens to
both sides of a live conversation, transcribes and translates on the fly,
summarizes what's been said, and gives you contextual coaching as you speak.
Built for **mock interviews**, sales calls, and difficult conversations.

100% native Swift. No webview, no virtual audio driver, no API keys.
The "brain" runs through your local **Claude Code CLI** (your existing
subscription/login), so there's nothing to configure and no key to leak.

> ⚠️ **Ethics/use**: great for practice, mock interviews, and preparing for
> hard conversations. Some real-world settings have rules about live assistance —
> know the context you're in. See [Responsible use](#responsible-use).

---

## What it does

- **Captures both sides natively** — your mic (`AVAudioEngine`) + the other
  person's audio from the system (`ScreenCaptureKit`, e.g. Zoom/Meet). Because
  the two sources are separate, *who spoke* is known by origin — no diarization.
- **Live transcription** (left pane) with speaker labels.
- **Line-by-line translation** when the conversation is in a foreign language.
- **Rolling summary** (top-right) of what's been said so far.
- **Contextual coaching** (bottom-right): "they asked X — answer like this",
  with a ready-to-say phrase in the conversation language + your native language.
- **Session brief** (mode: interview / sales / difficult / custom) + a manual
  question box you can type into mid-conversation.

Example (interview in English, native Portuguese):

```
[Interlocutor] So, why do you want to leave your current company?
  ↳ Então, por que você quer sair da sua empresa atual?

Coach ──────────────────────────────────────────────
GUIA:  Foque em crescimento, não em problemas. Nunca fale mal do empregador atual.
DIGA:  I'm looking for a role with more end-to-end ownership and technical growth.
  ↳    Busco um cargo com mais autonomia ponta a ponta e crescimento técnico.
KEYTERMS: end-to-end ownership · technical growth · scope
```

---

## Requirements

- **macOS 26 (Tahoe)** — uses the new on-device `SpeechAnalyzer` / `SpeechTranscriber`.
- **Xcode 26** (Swift 6.2).
- **Claude Code CLI** installed and logged in — the coaching/translation/summary
  brain shells out to `claude -p`. Verify with:
  ```sh
  claude --version   # should print a version
  claude -p "hi"     # should answer (i.e. you're logged in)
  ```
  Install: https://docs.claude.com/en/docs/claude-code

No Anthropic API key is used — the app reuses your CLI login.

---

## How to run

1. Open the project:
   ```sh
   open LiveCopilot.xcodeproj
   ```
2. In Xcode, select the **LiveCopilot** scheme and press **⌘R**.
3. On first launch, grant permissions when prompted:
   - **Microphone** — required (your side of the conversation).
   - **Screen & System Audio Recording** — optional but needed to hear the
     *other* person's audio (Zoom/Meet/system). Grant it in
     *System Settings → Privacy & Security → Screen & System Audio Recording*,
     then relaunch. Without it, the app runs mic-only.

If Xcode complains about signing, set your team under
*Signing & Capabilities*, or build with signing disabled for local runs.

---

## Full test walkthrough

A complete end-to-end test of all four lanes (transcription, translation,
summary, coaching):

1. **Set the brief** (bottom bar): Mode = *Entrevista*, Conversa = `en-US`,
   Nativo = `pt-BR`, STT = *Nativo (on-device)*.
2. Press **Iniciar**. Approve the mic prompt. The menu-bar mic dot turns on and
   the status reads **Ao vivo**. (First use of a language downloads its on-device
   model — needs network once.)
3. **Coaching (no audio needed):** type a question in the bottom box, e.g.
   *"Why do you want to leave your current company?"*, and press **Perguntar**.
   Within a couple of seconds a coach card appears with GUIA / DIGA / translation
   / KEYTERMS. Send a second question to see the warm session respond faster.
4. **Live transcription + translation:** with a headset/Zoom call running (and
   Screen Recording granted), have the other side speak. Their line appears
   under `[Interlocutor]` with a `↳` translation, and a coach card is generated
   automatically at the end of their turn. Speak yourself to see `[Você]` lines.
5. **Summary:** after ~30s of conversation, the top-right pane fills with up to
   5 bullets and refreshes as things progress.
6. **Silêncio** toggles the coach off (transcription keeps running).

First call to each lane pays a one-time CLI cold start (~5–10s); subsequent
calls reuse a warm `claude` process (~1–2s).

---

## How it works

```
AVAudioEngine (mic) ─────┐
                         ├─▶ AudioConverter (→16k mono) ─▶ NativeTranscriber (SpeechAnalyzer)
ScreenCaptureKit (sys) ──┘                                          │
                                                                    ▼
                                                             TranscriptBus (actor)
                                    ┌────────────────┬───────────────┬───────────────┐
                                    ▼                ▼               ▼               ▼
                              Translation        Summary         Coaching        SwiftUI
                              (haiku)            (haiku, 30s)    (sonnet, stream)  (2 panes)
                                    └────────────────┴───────────────┘
                                     persistent `claude -p` sessions (warm, per lane)
```

- **Brain via Claude Code CLI.** Each lane keeps a long-lived `claude -p` process
  in streaming-json mode (`--input-format stream-json --output-format stream-json`).
  Cold start is paid once; turns after that are just inference. System prompt and
  model (`haiku` / `sonnet`) are fixed per session; the coach streams tokens live.
- **Speaker by origin.** Mic = `self`, system audio = `other`. No diarization.
- **Swift Concurrency throughout.** Actors for shared state, `AsyncStream` for
  fan-out, cooperative cancellation for the coach (a new turn cancels the old).

### Project layout

```
LiveCopilot/
├── Audio/    AudioCapture (mic + ScreenCaptureKit), AudioConverter
├── STT/      SttProvider (protocol), NativeTranscriber (SpeechAnalyzer)
├── Bus/      TranscriptBus (actor + fan-out + rolling window)
├── Brain/    ClaudeClient (CLI resolver), ClaudeSession (warm process),
│             Translation / Summary / Coaching lanes, Prompts
├── Model/    AppModel (@Observable), SessionCoordinator, SessionBrief, Types
└── Views/    RootView, TranscriptPane, SummaryPane, CoachingPane, ControlsBar
```

---

## Responsible use

This is a practice and preparation tool. In live, real processes (interviews,
exams, etc.) some organizations prohibit real-time assistance — respect the
rules of the context you're in. The authors provide this for legitimate training
and accessibility use.

## Privacy

- Speech-to-text is **on-device** (`SpeechAnalyzer`) — audio doesn't leave your
  Mac for transcription.
- Coaching/translation/summary go through your **local Claude Code CLI**, using
  your own account. No third-party keys are stored by this app.

## License

MIT — see [LICENSE](LICENSE).

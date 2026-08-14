# Changelog

## [2.0.0](https://github.com/feliperun/cueme/compare/v1.4.1...v2.0.0) (2026-08-14)


### ⚠ BREAKING CHANGES

* store the corpus as an OKF v0.2 bundle with one entity
* store the corpus as an OKF v0.2 bundle with one entity ([#46](https://github.com/feliperun/cueme/issues/46))
* knowledge-entities.json is no longer read or written.
* notes are no longer readable without migrating the archive to the OKF corpus first — see scripts/migrate-okf.py. The JSON export is removed.
* `SessionRecord` no longer exists; `MemoryNote` is the only name for the durable base entity. Archives under ~/Library/Application Support/CueMe/sessions are no longer read.

### Features

* collapse projects and people into notes ([3fc64e1](https://github.com/feliperun/cueme/commit/3fc64e1f0bc9ec8209be275d8f8d3b986a3e6adc))
* delete session.json and the JSON export ([a7f3c88](https://github.com/feliperun/cueme/commit/a7f3c885e2ed59ba675daad1a7f3b7b25fd198e4))
* **library:** add an explicit corpus refresh ([afa0e01](https://github.com/feliperun/cueme/commit/afa0e01035342ead13c1b2f1d14d7955a6565cfd))
* **library:** nest notes by drag and drop ([1ccd7df](https://github.com/feliperun/cueme/commit/1ccd7dfef8ef08bd376b1b6eaa6dc5097d7b89ec))
* **okf:** add corpus layout and slug rules ([4cf17dd](https://github.com/feliperun/cueme/commit/4cf17dd6e147e18aa0805a2c29795d91afaee708))
* **okf:** add inline item attribute codec ([62cf1c8](https://github.com/feliperun/cueme/commit/62cf1c884d554cdd0dd9c0e4d545d96bbb7d0976))
* **okf:** add section marker splitter and escaping ([f613e47](https://github.com/feliperun/cueme/commit/f613e472be90e2bf6c0c70981dfa82785e23f758))
* **okf:** add YAML frontmatter codec ([a09b4fa](https://github.com/feliperun/cueme/commit/a09b4faf13880fb45efb8eae1dcac1116821ff25))
* **okf:** emit per-level indexes, append-only log and corpus AGENTS.md ([2ed1c90](https://github.com/feliperun/cueme/commit/2ed1c909d25f234ec99b0a89a2de0a6a9ee2abc6))
* **okf:** load and save the note tree ([4e54819](https://github.com/feliperun/cueme/commit/4e54819de6ecb78f0f7bd9653f2efe1c764c5a5b))
* **okf:** move and rename notes, rewriting inbound links ([ab49e75](https://github.com/feliperun/cueme/commit/ab49e7567e679a734d0fe1084da662e753c1f1e4))
* **okf:** read note markdown as the durable source ([8cefeee](https://github.com/feliperun/cueme/commit/8cefeee55560fbd98ab1790cfd87e40e3691e492))
* **okf:** write and read raw/transcript.md ([b7e7252](https://github.com/feliperun/cueme/commit/b7e72523a208d4a6c2fd5f910158bb81ef485910))
* **okf:** write note markdown as an OKF concept doc ([f4934ee](https://github.com/feliperun/cueme/commit/f4934ee76175293a59d0ec2322aa0fd51bc16120))
* rename SessionRecord to MemoryNote and adopt greenfield policy ([b7d3fd8](https://github.com/feliperun/cueme/commit/b7d3fd8dcef37f3a7f50add10c932d6efd090f08))
* **scripts:** add the one-shot OKF migration ([0ba359a](https://github.com/feliperun/cueme/commit/0ba359a2888ae24489d38a5ee2f7d1429f72418a))
* store the corpus as an OKF v0.2 bundle with one entity ([12d1d38](https://github.com/feliperun/cueme/commit/12d1d3894b92d275126c294bc28a8e63bdcbd430))
* store the corpus as an OKF v0.2 bundle with one entity ([#46](https://github.com/feliperun/cueme/issues/46)) ([12d1d38](https://github.com/feliperun/cueme/commit/12d1d3894b92d275126c294bc28a8e63bdcbd430))


### Bug Fixes

* **e2e:** realign the memory scenarios with the one-entity model ([9297824](https://github.com/feliperun/cueme/commit/92978248abecd2473dfd30be1bd23179f8a27163))
* **model:** make MemoryNote equality structural ([b4e661b](https://github.com/feliperun/cueme/commit/b4e661b852e31bf54d5187aa7393031afe37e92a))
* **model:** refuse to read or write an unmigrated archive ([e138922](https://github.com/feliperun/cueme/commit/e138922aafc3d7e5bffc83f256c839e6100f9930))
* **tests:** give each runner process its own UI-test corpus root ([434f6d7](https://github.com/feliperun/cueme/commit/434f6d7aa11d03b8e7523dad402b51f8c5c592ad))


### Performance Improvements

* **okf:** append transcript turns during live sessions ([8f0c802](https://github.com/feliperun/cueme/commit/8f0c80277a7bfa896c0027913c4e874ed7d1c51a))

## [1.4.1](https://github.com/feliperun/cueme/compare/v1.4.0...v1.4.1) (2026-08-07)


### Bug Fixes

* bound live teardown and restore coach streaming ([#44](https://github.com/feliperun/cueme/issues/44)) ([aeb3f0c](https://github.com/feliperun/cueme/commit/aeb3f0c66bba2411a3cf774c160c9ab2b58abb51))

## [1.4.0](https://github.com/feliperun/cueme/compare/v1.3.0...v1.4.0) (2026-08-06)


### Features

* **gh-37:** add hierarchical project tree ([8fd165e](https://github.com/feliperun/cueme/commit/8fd165ea5721c98f1467f89d4df80bc317ade6e2))
* **gh-37:** align note list filters and counts ([641bd22](https://github.com/feliperun/cueme/commit/641bd22f4c979ca975601e90cf0c7160dcd57575))
* **gh-37:** migrate workspace shell chrome ([eb7eda6](https://github.com/feliperun/cueme/commit/eb7eda6a123c371d50f873d6034c459746437d79))


### Bug Fixes

* **gh-37:** stabilize workspace UI contracts ([3214bda](https://github.com/feliperun/cueme/commit/3214bda7ff6248bedd9d11e9b16bc8807314da92))
* stabilize live recording transcription and coach ([e8d0b67](https://github.com/feliperun/cueme/commit/e8d0b67ee13f31b52c4206398cb8870460e0102c))
* stabilize live recording transcription and coach ([2474fab](https://github.com/feliperun/cueme/commit/2474fab2fbc0c30d1847e67e3e04c54172281ed5))
* stabilize live recording transcription and coach ([#40](https://github.com/feliperun/cueme/issues/40)) ([e8d0b67](https://github.com/feliperun/cueme/commit/e8d0b67ee13f31b52c4206398cb8870460e0102c))

## [1.3.0](https://github.com/feliperun/cueme/compare/v1.2.0...v1.3.0) (2026-07-26)


### Features

* **updates:** show what an update check actually answered ([3de43b5](https://github.com/feliperun/cueme/commit/3de43b5df33f1911b12f5ebec298e5784b9c7474))

## [1.2.0](https://github.com/feliperun/cueme/compare/v1.1.0...v1.2.0) (2026-07-24)


### Features

* **audio:** in-progress external audio import (share extension + inbox) ([8d90903](https://github.com/feliperun/cueme/commit/8d90903fd6a80f9ee484ea8335280c824e06bc9e))
* **ui:** note-first three-column workspace redesign ([4cb4305](https://github.com/feliperun/cueme/commit/4cb4305ba59fabab54681faa0d7dd8f16df0a96e))
* **ui:** note-first three-column workspace redesign ([a785259](https://github.com/feliperun/cueme/commit/a785259f850cc8e458d642c3006b647d587838ff))


### Bug Fixes

* **ui:** keep note/review editors focusable under Ask CueMe bar ([9a13a29](https://github.com/feliperun/cueme/commit/9a13a2931f7daa206cc39bf434b025c56fc3385b))

## [1.1.0](https://github.com/feliperun/cueme/compare/v1.0.0...v1.1.0) (2026-07-16)


### Features

* add native Markdown block editor ([#28](https://github.com/feliperun/cueme/issues/28)) ([0e29f05](https://github.com/feliperun/cueme/commit/0e29f0581aa0cd3a45e51e48c8feed2cc865937a))

## [1.0.0](https://github.com/feliperun/cueme/compare/v0.14.0...v1.0.0) (2026-07-15)


### ⚠ BREAKING CHANGES

* CueMe becomes a file-first second brain centered on Markdown notes, projects, labels, attachments, semantic memory, and meeting intelligence.

### Features

* turn CueMe into a file-first personal second brain ([a3933c0](https://github.com/feliperun/cueme/commit/a3933c048cf8c8521b2212642bb96376b496fd47))


### Bug Fixes

* preserve macOS capture permissions ([800ff6e](https://github.com/feliperun/cueme/commit/800ff6e7dbd947c2de061efbb4f1dc8d7d80fdb0))
* preserve macOS capture permissions ([497635d](https://github.com/feliperun/cueme/commit/497635d4904807052a0a671c3411cdfe0e0fc85f))

## [0.14.0](https://github.com/feliperun/cueme/compare/v0.11.0...v0.14.0) (2026-07-15)


### Features

* add longitudinal semantic meeting memory ([4a560de](https://github.com/feliperun/cueme/commit/4a560de0558315bed08c49f4206f79808fcef11b))

## [0.11.0](https://github.com/feliperun/cueme/compare/v0.10.0...v0.11.0) (2026-07-15)


### Features

* add supported Voice Memos sharing ([9f510d3](https://github.com/feliperun/cueme/commit/9f510d3cb6bc424472827ae34bc83b09b65781d7))

## [0.10.0](https://github.com/feliperun/cueme/compare/v0.9.1...v0.10.0) (2026-07-15)


### Features

* add adaptive live meeting experience ([09291b0](https://github.com/feliperun/cueme/commit/09291b03c4397d39734523ac9cc31749147912d9))
* import meeting audio and search session memory ([5577b22](https://github.com/feliperun/cueme/commit/5577b228698ff8e5a1f8ec4718daef9c31c57def))

## [0.9.1](https://github.com/feliperun/cueme/compare/v0.9.0...v0.9.1) (2026-07-14)


### Bug Fixes

* launch ad hoc releases with Sparkle ([84b1de5](https://github.com/feliperun/cueme/commit/84b1de5f14eec0bc537bdb9a1cc10945952b5d77))
* launch ad hoc releases with Sparkle ([6c802b0](https://github.com/feliperun/cueme/commit/6c802b0a5eddbab62d7d6434fa242df46799a92d))

## [0.9.0](https://github.com/feliperun/cueme/compare/v0.8.0...v0.9.0) (2026-07-14)


### Features

* add adaptive meeting intelligence ([9a47cf3](https://github.com/feliperun/cueme/commit/9a47cf31c2a333bf797ae3de138e484f2eef97d8))
* add Deepgram streaming transcription ([108a8b2](https://github.com/feliperun/cueme/commit/108a8b20e8edd547fa5776f6be62993b709c7bf3))
* add meeting memory workspace ([382f313](https://github.com/feliperun/cueme/commit/382f31307bb06ba735a2074225483881bd1322de))
* add reusable meeting contexts ([d7b8c6f](https://github.com/feliperun/cueme/commit/d7b8c6f669ceb0cdc47ffc56b2394effc4339d01))
* improve audio quality and polish workspace ([4b76b24](https://github.com/feliperun/cueme/commit/4b76b24124e61828014f132bd2f48b9bc6b49e11))
* ship meeting memory and intelligent transcription ([1cfd72a](https://github.com/feliperun/cueme/commit/1cfd72a8de57cbc316b633683d01f6f701856b11))

## [0.8.0](https://github.com/feliperun/cueme/compare/v0.7.1...v0.8.0) (2026-07-14)


### Features

* add long-call recovery and provider failover ([826d86d](https://github.com/feliperun/cueme/commit/826d86d648976655bb810d085e67be50a624051f))

## [0.7.1](https://github.com/feliperun/cueme/compare/v0.7.0...v0.7.1) (2026-07-14)


### Bug Fixes

* make release assets workflow dispatchable ([04d2a74](https://github.com/feliperun/cueme/commit/04d2a7481caffa516250bc3675aff9961f1b9b30))

## [0.7.0](https://github.com/feliperun/cueme/compare/v0.6.0...v0.7.0) (2026-07-14)


### Features

* ship glanceable resilient live coaching ([cc29116](https://github.com/feliperun/cueme/commit/cc29116c633603277246e90730799d8a15061ed9))

## [0.6.0](https://github.com/feliperun/cueme/compare/v0.5.0...v0.6.0) (2026-07-14)


### Features

* ship reliable fast live coaching ([1014084](https://github.com/feliperun/cueme/commit/10140844262c07af01bf2182a82e4a6c392a7583))

## [0.5.0](https://github.com/feliperun/cueme/compare/v0.4.0...v0.5.0) (2026-07-13)


### Features

* DeepSeek V4 coach (Pro/Flash) + new-session UX ([78408a9](https://github.com/feliperun/cueme/commit/78408a9cf5b52a69b944eb0173bb092f0af24002))
* DeepSeek V4 coach via direct API (Pro/Flash) ([7ef902c](https://github.com/feliperun/cueme/commit/7ef902cfb9163f8547c1730b1634a13aaf5356d4))
* persist coach model + "New session" one-click restart ([2cc7580](https://github.com/feliperun/cueme/commit/2cc75802cad24c299d99cd36dab420d500b1eec2))

## [0.4.0](https://github.com/feliperun/cueme/compare/v0.3.0...v0.4.0) (2026-07-13)


### Features

* app icon, About window, and packaging tooling ([65e706b](https://github.com/feliperun/cueme/commit/65e706b4684dd5d921caca75bf2bf29ede487e21))
* command-center visual theme + context-leak guard for the coach ([0e9daf3](https://github.com/feliperun/cueme/commit/0e9daf340062b81dc6036a5722944ee322e7a208))
* compact-first redesign — friend-style hints, CV-aware coach, echo dedup ([b4a2746](https://github.com/feliperun/cueme/commit/b4a274684d6c583a859abf99761cb976a0a3f6df))
* expert coach — three-specialist persona + per-mode playbooks ([4c24463](https://github.com/feliperun/cueme/commit/4c2446310ee7dfaf7745277b4c625448e6dad757))
* export/copy a session as JSON ([65008c0](https://github.com/feliperun/cueme/commit/65008c0122a250686751488746fd692a33e22ad0))
* faster, easier-to-read coach card ([9ea7ca0](https://github.com/feliperun/cueme/commit/9ea7ca0067d775198caa998bf8910d905892039c))
* global ⌥Space show/hide hotkey + menu bar controls ([3921391](https://github.com/feliperun/cueme/commit/3921391089f5bf7ac1379ffbb696779dde9d0c7a))
* harden coach role, succinct emoji cards, AEC, model picker, bigger UI ([a31c1e1](https://github.com/feliperun/cueme/commit/a31c1e1517357d3e12b35380e1b1ab3767ee4d6d))
* initial LiveCopilot — native macOS real-time conversation copilot ([fbf99e9](https://github.com/feliperun/cueme/commit/fbf99e9808268a99e75bcf5c4eada5d34065a78e))
* meeting mode — synced audio recording + waveform playback ([3c24aec](https://github.com/feliperun/cueme/commit/3c24aec653d7052f899faf0544f5b82ec02c4c2e))
* on-device translation highlighting (NaturalLanguage), tiered not bold ([dd69c8a](https://github.com/feliperun/cueme/commit/dd69c8a1701272db17cde560fd4d822b0e1a6797))
* opt-in acoustic echo cancellation + default coach to Sonnet ([1612f02](https://github.com/feliperun/cueme/commit/1612f02571dc9d3f4fa01e33262ed525eaacf184))
* session history — browse past training and live sessions ([caff74c](https://github.com/feliperun/cueme/commit/caff74c2077c144db4975de43ce0f35041e1135e))
* training mode — adaptive voice interviewer + e2e test harness ([cdc4f2e](https://github.com/feliperun/cueme/commit/cdc4f2eff7c26cb6e2eb4b6daf6db477371b30b0))
* training-mode toggle in the header ([be0351d](https://github.com/feliperun/cueme/commit/be0351d8490b108fd310ec4f80a8ade4dc85a7c9))


### Bug Fixes

* remove conflicting bump-patch-for-minor-pre-major from release-please ([5a0eb8b](https://github.com/feliperun/cueme/commit/5a0eb8b3f15db4b6758b42e975d24f5931e29b6a))


### Performance Improvements

* native on-device translation + session prewarm for realtime latency ([10bd433](https://github.com/feliperun/cueme/commit/10bd433eaeabaa84e857f30573e07512ee1249c8))

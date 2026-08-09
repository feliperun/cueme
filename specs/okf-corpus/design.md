# Design — OKF v0.2 corpus

The authoritative description of the format and the code that produces it. Where
this document and a golden file in [`contracts/`](contracts/) disagree, the
**golden file wins** and the disagreement is a stop-and-report.

---

## 1. Layout

```
<root>/
  AGENTS.md                  # operational schema for agents; not part of the bundle
  index.md                   # reserved — the only file carrying okf_version
  log.md                     # reserved — append-only history
  acme.md                    # type: Note
  acme/                      # exists only because acme has children or raw/
    index.md
    atas.md
    atas/
      reuniao-1.md
      reuniao-1/
        raw/
          transcript.md      # type: Transcript
          self.m4a
          other.m4a
          attachments/proposta.pdf
      reuniao-2.md
  pessoas.md
  pessoas/
    marina-souza.md
  inbox.md                   # default parent for a new session; an ordinary note
  inbox/
```

**A note is `<slug>.md`.** The sibling directory `<slug>/` is created only when the
note gains a child or a `raw/` asset, and removed when it loses the last of both.
A plain text leaf is a single file.

**One entity.** There is no project and no person type. A project is a note; a
person is a note. Only two relations exist:

- **Hierarchy** — parent/child, expressed by the path. It lives in the path and
  nowhere else, because dragging a folder in Finder has to work.
- **Link** — an untyped edge: a path in `x_cueme_links`, or a Markdown link in the
  body. OKF treats links as untyped directed edges; the surrounding prose says
  what the relation means.

**Capture vs. knowledge.** `raw/` holds what was captured (verbatim transcript,
audio, attachments). The `.md` holds what was extracted. This is what keeps the
concept document human-sized, and it is the reason the transcript is not inside
it — a transcript is a source, not a concept. Unlike the reference OKF wiki
template, `raw/` here is **not** agent-read-only: the user may correct a turn, and
the model carries the audit trail (`originalText` / `editedAt`). Pointwise
correction yes; wholesale AI rewrite no.

### Reserved names

| Name | Where | Why |
|---|---|---|
| `index.md` | any directory | OKF directory listing |
| `log.md` | any directory | OKF change history |
| `AGENTS.md` | root only | operational schema |
| `raw` | inside a note folder | capture directory |

A slug that would collide with a reserved name is rejected and the next free
candidate is used.

### Slugs

Fold diacritics, replace runs of non-alphanumerics with `-`, lowercase, trim to 54
characters. Reuse the existing implementation in `ProjectWorkspaceStore.slug`
(moving it into `OKFBundle`). Uniqueness is **per directory**, not global;
collisions get `-2`, `-3`, … A session created without a title is named
`yyyy-MM-dd-HHmm` in local time.

**Renaming the file follows only an explicit user rename** (`titleSource == .user`).
An AI-generated title changes during post-processing and must never cause file
churn.

### `type` vocabulary

In use: `Note`, `Transcript`. Reserved for a future derived layer, not emitted by
this plan: `Concept`, `Synthesis`, `Comparison`, `Source Summary`. OKF requires
consumers to tolerate unknown types, so adding one later breaks nothing.

---

## 2. The four rules

Every field decision follows from these. They are what make the format testable
rather than a matter of taste.

1. **No write-only fields.** Everything emitted is parsed back. A *rendering*
   derived from a parsed field — the `# H1`, the `00:42` clock, a footnote
   definition — is allowed, because it holds no independent state. Exactly one
   section is derived-only and it is named in §4.10.
2. **One home per field.** No field appears in two places with a precedence rule.
   *Corollary:* hierarchy lives in the path and is never written to frontmatter.
3. **No cosmetic transform on parsed text.** Parsed text is never wrapped in
   `_…_`, `>` or `**…**`. A marker may tag a line's role; it may not decorate its
   content. This is what makes byte-idempotence provable.
4. **`x_cueme_*` only when OKF has no honest home** — meaning the OKF key's
   *semantics* match, not merely its shape.

---

## 3. Frontmatter

Block style throughout. Flow style appears only inside inline item comments (§4),
where it must fit on one line. Emit keys in exactly this order; omit a key entirely
when the rule says so. Unknown keys are re-emitted verbatim, in their original
order, after all known keys.

```yaml
type: Note
title: <displayTitle ?? fallback>
description: <goal>                       # omit when empty
tags:                                     # labels — omit when empty
  - frota
created_at: <startedAt>
updated_at: <modifiedAt>
generated:
  by: <producer>                          # cueme/<CFBundleShortVersionString>
  at: <modifiedAt>
sources:                                  # omit when empty; sorted by id
  - id: ev-<evidence uuid>
    resource: raw/transcript.md#t-<turn uuid>   # drop the fragment when turnID is nil
    title: <quote>
    x_timestamp: <seconds, 3 decimals>
    x_turn_id: <uuid>                     # omit when nil
x_cueme_links:                            # omit when empty; sorted
  - /pessoas/marina-souza.md
x_cueme_kind: meeting                     # MemoryNoteKind.rawValue
x_cueme_mode: meeting                     # Mode.rawValue
x_cueme_origin: live                      # SessionOrigin.rawValue
x_cueme_training: false
x_cueme_title_source: user                # NoteTitleSource.rawValue
x_cueme_ended_at: <endedAt>
x_cueme_lang:
  conversation: pt-BR
  native: pt-BR
x_cueme_participant_names:                # omit when empty; keys sorted
  other: Marina
  self: Felipe
x_cueme_models:                           # omit when both nil; omit the nil member
  coach: opus
  summary: sonnet
x_cueme_audio:                            # omit when hasAudio is false
  duration: 1785.4
  recording_started_at: <date>            # omit when nil
x_cueme_integrity:
  errors: 0
  recoveries: 1
x_cueme_transcript:                       # omit when the note has zero turns
  file: raw/transcript.md
  turns: 214
x_cueme_attachments:                      # omit when empty; sorted by id
  - id: <uuid>
    file: raw/attachments/proposta.pdf
    kind: document                        # NoteAttachmentKind.rawValue
    added_at: <date>
x_cueme_vocabulary:                       # omit when both members empty
  keyterms:                               # sorted
    - monorepo
  replacements:                           # keys sorted
    mono rapo: monorepo
x_cueme_coach_feedback:                   # omit when empty; keys sorted
  a1000000-0000-0000-0000-000000000001: helpful
```

**Dates** are ISO 8601 with fractional seconds in UTC: `2026-08-08T14:30:11.000Z`.
**Doubles** are quantized to 3 decimals at the point of assignment in the domain,
not at serialization time — that is what makes idempotence independent of Yams'
float formatting — and emitted with Swift's default `Double` description, which is
the shortest round-trippable form (`42.0`, `0.94`, `1785.4`).
**Dictionaries and sets** are emitted sorted by key so they round-trip.

### Quoting policy

Byte-exactness against the golden files requires this to be explicit rather than
left to the emitter's defaults. Do not accept whatever Yams does by default —
configure it, and add a small helper if needed.

| Value | Style |
|---|---|
| date | always double-quoted — unquoted it re-parses as a YAML 1.1 timestamp, not a string |
| path, URI, fragment | always double-quoted — they carry `/`, `#`, `.` |
| number, boolean, `null` | plain |
| enum raw value, ordinary text | plain |
| text that is empty, or would parse as a number / boolean / date, or begins with a YAML indicator, or contains `: ` or ` #`, or has leading or trailing whitespace | double-quoted |

The same policy applies inside the flow mappings of item attributes (§4.2).

### Native OKF mappings

| CueMe | OKF key | Why it is honest |
|---|---|---|
| document class | `type` | required by the spec |
| `displayTitle` | `title` | direct |
| `goal` | `description` | it *is* "what this note is for". Today it lives only in `session.json`, so it is **lost on any external edit** — this closes a real hole and feeds `index.md`. |
| `labels` | `tags` | direct |
| `MemoryEvidence[]` | `sources[]` + `[^id]` footnote refs | evidence *is* per-claim provenance pointing at the capture file, which is exactly what `resource` means. Deduplicates for free: today the same evidence is stored once per item citing it. |
| document provenance | `generated: {by, at}` | emitted, not parsed — it describes the document, not domain state. `by` is injectable so tests can pin it. |

### Rejected native mappings

Recorded so nobody relitigates them.

- **`titleSource` → `generated.by`** — no. `generated` describes the document;
  `titleSource` describes one field. Overloading it would make a user-renamed note
  claim a human authored the whole file.
- **`SessionTakeaway.isDone` → `status`** — no. OKF `status` is *document*
  lifecycle (`draft`/`stable`/`deprecated`). A note with one finished action is not
  a deprecated document. `isDone` is a GFM checkbox: readable and editable in any
  editor, and exactly the "structural markdown over prose" the spec asks for.
- **`status` / `stale_after`** — not emitted. CueMe has no lifecycle concept to
  back them, and inventing one adds a field nothing reads.
- **`usage_window`** — would duplicate `created_at`. Rule 2.
- **`verified[]`** — not emitted; no affordance produces it. It is the natural home
  for a future "I reviewed this AI summary" action. Noted here so nobody invents
  `x_cueme_reviewed` instead.

---

## 4. Body

### 4.1 Structure

```
# <title>

<user body>

<!-- cueme:minutes -->        …
<!-- cueme:takeaways -->      …
<!-- cueme:decisions -->      …
<!-- cueme:open-questions --> …
<!-- cueme:follow-up -->      …
<!-- cueme:notes -->          …
<!-- cueme:coach -->          …
<!-- cueme:artifacts -->      …
<!-- cueme:sources -->        …
<residual>
```

A marker is `<!-- cueme:<name> -->` at column 0. **Section identity comes from the
marker; the heading under it is decoration** and is regenerated on write. A section
runs from its marker to the next `^<!--\s?cueme:` line or EOF — there are no
closing tags. Sections are emitted in the order above and omitted entirely when
empty. Reordering them in the file does not break parsing; writing restores
canonical order.

**The user body needs no fence.** It is everything between the `# H1` and the first
marker. The old `<!-- cueme:body:start -->` / `<!-- cueme:body:end -->` sentinels are
deleted, so a hand-written note contains zero machine markers — which is the entire
point of having a human corpus.

Marker names are English; headings are pt-BR. Identifiers are code
(`AGENTS.md` §3), and this way changing the UI language never touches the on-disk
contract.

### 4.2 Item attributes

Non-visible fields ride in a flow mapping inside an HTML comment at the end of the
item's anchor line:

```
- [ ] Solicitar propostas[^ev-…] <!--cueme {id: 7000…01, at: …, confidence: 0.94, assignee: Marina, due: 2026-08-15}-->
```

Only `text`, the done-checkbox and evidence refs are visible-and-parsed. `assignee`,
`due` and `confidence` stay in the comment: rendering them as prose (`— @Marina, até
15/08`) and parsing them back is exactly the natural-language parser this design
exists to avoid, and it would give one field two homes.

Attribute keys are short and fixed per grammar (§4.4–§4.9). Absent attribute →
`nil`. A malformed comment makes the line plain text (§5 rule 6).

### 4.3 Five grammars

| # | Grammar | Used by |
|---|---|---|
| A | prose | `follow-up` |
| B | anchored H3 blocks | `minutes`, `coach`, `artifacts` |
| C | list items | `takeaways`, `decisions`, `open-questions`, `notes` |
| D | footnote definitions (derived-only) | `sources` |
| E | transcript turns | `raw/transcript.md` |

**Grammar A** — content is the section's lines minus a leading ATX heading.

**Grammar B** — an optional preamble (lines before the first anchor) followed by
zero or more blocks. A block starts at `### <label> <!--cueme {…}-->` and runs to the
next anchor or the section end.

**Grammar C** — one item per anchor line; no preamble. Lines that are not items go
to residual.

### 4.4 `minutes`

```markdown
<!-- cueme:minutes -->
## Ata

A equipe aprovou a migração da frota.

### Mobilidade <!--cueme {id: 6000…01, at: 2026-08-08T14:58:00.000Z}-->

Troca gradual da frota, começando pela regional sul.
```

Grammar B. Preamble → `minutes.overview`. Each block → `MeetingTopic`
(`id`, `title` = the H3 label, `summary` = the block body, `at` → `updatedAt`).
There is no `### Assuntos` grouping heading — it carried no state and cost a level
of nesting. `minutes.updatedAt` is not emitted; it is the max of the topics'
`updatedAt`, or nil when there are none.

### 4.5 `takeaways`

```markdown
<!-- cueme:takeaways -->
## Pendências

- [ ] Solicitar propostas[^ev-3000…01] <!--cueme {id: …, at: …, confidence: 0.94, assignee: Marina, due: 2026-08-15}-->
- [x] Reservar orçamento <!--cueme {id: …, at: …}-->
```

Grammar C. Line regex:
`^- \[( |x)\] (.*?)(?:\s*<!--cueme (\{.*\})-->)?\s*$`.
Checkbox → `isDone`. Attributes: `id`, `at` → `createdAt`, `confidence`, `assignee`,
`due` → `dueAt`. Evidence refs are extracted from the text first (§4.10).

### 4.6 `decisions` and `open-questions`

```markdown
<!-- cueme:decisions -->
## Decisões

- Adotar veículos elétricos no próximo trimestre[^ev-3000…01] <!--cueme {id: …, confidence: 0.97}-->
```

Grammar C, `^- (.*?)(?:\s*<!--cueme (\{.*\})-->)?\s*$`. Attributes: `id`,
`confidence`, `supersedes` → `supersedesID`. Headings: `## Decisões`,
`## Questões em aberto`.

### 4.7 `notes`

```markdown
<!-- cueme:notes -->
## Anotações

- Orçamento reservado <!--cueme {id: …, t: 50, at: …}-->
```

Grammar C. Attributes: `id`, `t` → `timeOffset` (seconds), `at` → `createdAt`.
Emitted sorted by `timeOffset`.

### 4.8 `coach`

```markdown
<!-- cueme:coach -->
## Coach

### 00:47 <!--cueme {id: …, ts: …, kind: answer, severity: info, keyterms: [fleet, TCO]}-->

Responda com MOTIVO → EVIDÊNCIA → IMPACTO.

<!--cueme:say-conv-->We can pilot ten vehicles next quarter.
<!--cueme:say-native-->Podemos pilotar dez veículos no próximo trimestre.
```

Grammar B. The H3 label is a rendered clock (`ts - startedAt`) and is **not**
parsed; `ts` comes from the attribute. Block body up to the first `say-*` line →
`guidePT`. The `say-conv` / `say-native` sub-lines carry their payload
**undecorated** — no `>` quoting, because rule 3 forbids a transform that has to be
inverted exactly. `keytermsConversation` is the `keyterms` list. `isStreaming` is
transient and always false at save. Cards with no content are not emitted.

### 4.9 `artifacts`

```markdown
<!-- cueme:artifacts -->
## Conteúdo gerado

### Follow-up <!--cueme {id: …, kind: answer, at: …}-->

Oi Marina, seguem os pontos do nosso alinhamento.
```

Grammar B, no preamble. H3 label → `title`. Attributes: `id`,
`kind` → `SessionArtifactKind`, `at` → `createdAt`.

### 4.10 `sources` — the one derived-only section

```markdown
<!-- cueme:sources -->
[^ev-3000…01]: O veículo elétrico será adotado no próximo trimestre.
```

`sources[]` in the frontmatter is the single home for evidence (rule 2). This
section exists so `[^ev-…]` references resolve in any Markdown renderer, and is
**regenerated from the frontmatter, never parsed**. It is the sole exception to
rule 1, and it is allowed because it carries no state the frontmatter does not.

Any line here that does not match `^\[\^ev-[0-9a-fA-F-]{36}\]: ` goes to residual.
That is what preserves a `## Apêndice` the user appends at the end of the file.

**Evidence refs in item text.** On write, `[^ev-<id>]` is appended to the item text
for each of its evidence entries. On read, refs whose id resolves in `sources[]` are
stripped and rebuilt into `[MemoryEvidence]`; a ref that does not resolve is left in
the text as literal characters, so round-trip still holds.

### 4.11 `raw/transcript.md`

Golden file: [`contracts/transcript.md`](contracts/transcript.md). A separate
concept document with `type: Transcript`, its own small frontmatter
(`x_cueme_note_id`, `x_cueme_started_at`, `x_cueme_participant_names`) and a single
`<!-- cueme:transcript -->` section. It reuses the same splitter, the same attribute
codec and the same escape rule — no new parsing machinery.

```markdown
**Marina · 00:42** <!--cueme {id: …, sp: other, ts: "…"}-->
O veículo elétrico será adotado no próximo trimestre.

**Felipe · 00:51** <!--cueme {id: …, sp: self, ts: "…", src: …, edited_at: "…"}-->
Vamos entregar no monorepo na sexta-feira.
<!--cueme:orig-->Vamos entregar no mono rapo na sexta.
<!--cueme:tr-->We will deliver on the monorepo on Friday.
```

Grammar E. A turn starts at a line matching
`^\*\*(.+?) · (\d{2}:\d{2}(?::\d{2})?)\*\* <!--cueme (\{.*\})-->$` and runs to the next
turn anchor or EOF. The bold name and the clock are **renderings** — the speaker
comes from `sp` and the time from `ts`. Attributes: `id`, `sp` (`Speaker.rawValue`),
`ts`, `src` → `sourceTurnID`, `edited_at` → `editedAt`. Body lines up to the first
`<!--cueme:orig-->` / `<!--cueme:tr-->` are the turn text; those two sub-lines carry
`originalText` and `translation` **undecorated** — no `_italics_`, because rule 3
forbids a transform that must be inverted exactly.

Only final turns are written. `isFinal` is therefore always true on read.

Appending during a live session (T019) writes new turn blocks at the end of the
file; the result must be byte-identical to a full render of the same turns.

### 4.12 Escaping

Applied to every free-text region — user body, topic summary, item text, coach
guide, `follow-up`, artifact body, transcript turn text:

- **write** — a line matching `^\\*<!--\s?cueme` gets one `\` prepended.
- **read** — a line matching `^\\+<!--\s?cueme` loses one leading `\`.

Exactly invertible, recursion-safe, and unit-testable in isolation. `\<` is a valid
Markdown escape that renders as `<`.

---

## 5. Parser robustness contract

Each line is a test.

1. **Unknown frontmatter key** → `unknownFrontmatterYAML`, re-emitted verbatim.
   Required by OKF ("consumers must preserve unknown keys").
2. **Unknown marker, or unclaimed lines in a known section** → `residualMarkdown`,
   re-emitted at the end. Required by `AGENTS.md` ("Files are authoritative"):
   without it, a `## Apêndice` written at the end disappears on the next autosave.
   Residual loses its original position; that is accepted and documented.
3. **Missing section** → empty collection, no error.
4. **`# H1` differs from frontmatter `title`** → **the H1 wins and `titleSource`
   becomes `.user`.** Somebody editing in Obsidian changes the heading, not the
   frontmatter. Write always emits `H1 == title`, so idempotence holds.
5. **Item with no `<!--cueme …-->`** (a hand-added `- [ ] nova ação`) → **mint a
   fresh UUID and adopt it.** This deliberately breaks read→write idempotence
   exactly once; the second write is idempotent. Test both halves.
6. **Malformed item line inside a known section** → not an item; appended to
   residual. Never silently dropped.
7. **No frontmatter, or empty `type`** → `read` returns `nil` and the loader skips
   the file, so a user's own `.md` dropped into a note folder is never eaten.

---

## 6. Model changes

### Deleted

| Field | Why |
|---|---|
| `projectID`, `personIDs` | the entities are gone; hierarchy and `links` replace them |
| `diagnostics` | dev telemetry, not user memory → `DiagnosticsLog` outside the corpus |
| `schemaVersion` | written, never branched on |
| `relativeFolderPath`, `archiveFolderName` | derived from the tree position |
| `summaryBullets` | a pure projection of `minutes.topics`; both readers become `minutes.topics.first` |
| `SessionTakeaway.createdInSessionID`, `MeetingReviewItem.createdInSessionID` | always the containing note's own id |

### Added

| Field | Why |
|---|---|
| `links: [String]` | the untyped relation, bundle-relative paths |
| `integrity: NoteIntegrity { recoveries, errors }` | what the Integrity panel actually shows |
| `transcript: TranscriptState` | see §7 |
| `unknownFrontmatterYAML: String` | OKF hard requirement |
| `residualMarkdown: String` | "Files are authoritative" hard requirement |

Both preservation fields are `String`, so no Yams type leaks into a `Codable`,
`Sendable`, `Hashable` model.

### Derived at load, never persisted

`path` — the note's position in the tree.

### Accepted losses

| Loss | Decision |
|---|---|
| `CoachCard.isStreaming` | transient; always false at save |
| non-final `TranscriptLine`s | the JSON persisted partials, Markdown will not. Partials are either promoted or garbage. A real, small fidelity regression. |
| a user-renamed heading | content survives (marker-keyed); the heading reverts to canonical. Non-destructive. |
| residual position | re-emitted at the end, not in place |

---

## 7. `TranscriptState` and the footgun

`loadNotes()` must not read `raw/` — a 200-note library would otherwise read 400
files and the small concept doc would buy nothing. But a `MemoryNote` whose
transcript was lazily left empty and then saved **erases `raw/transcript.md`**.

Close it in the type, not in discipline:

```swift
enum TranscriptState: Codable, Sendable, Hashable {
    case notLoaded(turns: Int)
    case loaded([TranscriptLine])
}
```

`TranscriptDocument.write` returns `nil` for `.notLoaded`, and `CorpusStore.save`
does not touch the file when it gets `nil`. Deleting a transcript you never loaded
becomes unrepresentable.

`CorpusStore.loadTranscript(for:)` fills it on demand: when the note is opened, and
in one full pass when `SemanticMemoryIndex` rebuilds — which already happens once
per launch, because `indexedFingerprint` hashes with `String.hashValue` and that is
seeded per process.

---

## 8. Modules

New directory `CueMe/Model/OKF/`. Everything in it depends only on `Foundation`,
`Yams` and the model value types — **never** on `AppModel` or `Views`. That rule is
what keeps `sentrux gate` healthy as the file count grows.

| File | Responsibility |
|---|---|
| `OKF/OKFBundle.swift` | layout, URLs, slugs, reserved names. `okfVersion`, `noteFileName`, `noteFolder`, `rawDirectory`, `slug`, `uniqueSlug(_:taken:)` |
| `OKF/OKFFrontmatter.swift` | **the only file importing Yams for documents.** `encode(_ ordered:) -> String`, `decode(_:) -> (fields, unknownYAML, bodyStart)?` |
| `OKF/OKFSectionMarkers.swift` | marker vocabulary, `split(_:) -> (h1, userBody, sections, residual)`, `escape`, `unescape` |
| `OKF/NoteItemAttributes.swift` | the `<!--cueme {…}-->` codec plus typed getters |
| `OKF/NoteDocumentWriter.swift` | `write(_ note:producer:) -> String` |
| `OKF/NoteDocumentReader.swift` | `read(_ markdown:slug:) -> MemoryNote?` |
| `OKF/TranscriptDocument.swift` | `write(_ note:) -> String?`, `read(_:) -> [TranscriptLine]` |
| `OKF/IndexDocument.swift` | per-directory `index.md`, append-only `log.md` |
| `OKF/CorpusAgentsDocument.swift` | writes the corpus `AGENTS.md` when absent; never overwrites |
| `OKF/BacklinkIndex.swift` | `references(to:)`, `rewrite(from:to:) -> Int` |
| `Model/NoteTree.swift` | parent/child, ordering, move validation |
| `Model/CorpusStore.swift` | replaces `SessionStore` |
| `Model/DiagnosticsLog.swift` | 500-entry ring + JSONL in `~/Library/Logs/CueMe/`, 7-day rotation |

```swift
enum CorpusStore {
    nonisolated(unsafe) static var rootOverride: URL?
    static var rootURL: URL { get }                      // same UserDefaults key
    static func setRoot(_ url: URL) throws

    static func noteURL(for note: MemoryNote) -> URL
    static func noteFolder(for note: MemoryNote) -> URL
    static func prepareNote(id: UUID, startedAt: Date, under parent: MemoryNote?) -> URL?

    @discardableResult static func save(_ note: MemoryNote) -> URL?
    static func loadNotes() -> [MemoryNote]              // reads .md only, never raw/
    static func loadTranscript(for note: MemoryNote) -> MemoryNote
    static func appendTranscript(_ lines: [TranscriptLine], to note: MemoryNote)
    static func delete(_ note: MemoryNote)

    static func move(_ note: MemoryNote, under parent: MemoryNote?) -> MemoryNote?
    static func rename(_ note: MemoryNote, to title: String) -> MemoryNote?

    static func writeIndexes(_ notes: [MemoryNote])
    static func appendLog(_ entries: [LogEntry], on day: Date)
    static func corpusChanged(since token: CorpusToken) -> Bool
}
```

**Deleted:** `Model/SessionArchive.swift`, `Model/NoteDocument.swift`,
`Model/ProjectWorkspaceStore.swift`, `Views/HistorySessionDiagnostics.swift`.
`Model/LiveSnapshotWriter.swift` is rewritten (T019).

**Yams is used** in `OKFFrontmatter` and `NoteItemAttributes`, and in the Python
side of the migration. **It is not used** for section splitting, marker scanning,
escaping or item line shaping — that is plain `String` work, and Yams has no notion
of Markdown.

### The two-object invariant

A note is `<slug>.md` plus, conditionally, `<slug>/`. Move and rename must carry
both, in the order **folder first, then file**, rolling the folder back if the file
step fails. A directory with no sibling `<slug>.md` is an inconsistency, not a data
loss: its children still load normally and the orphan is reported to the log.

---

## 9. Blast radius

- `session.json` — write, discovery loop, encoders, plus `docs/ARCHITECTURE.md`,
  `docs/ABSTRACTIONS.md`, `README.md`.
- `SessionStore` → `CorpusStore` — roughly 20 call sites plus 8 test files holding
  `rootOverride`.
- `LiveSnapshotWriter` — 8 call sites in `SessionCoordinator`,
  `AppModel+SessionMemory`, `AppModel`.
- `relocate` and `assignProject` — deleted.
- `KnowledgeProject`, `KnowledgePerson`, `KnowledgeEntityStore`,
  `ProjectWorkspaceStore` — deleted. `KnowledgeEntityStore.timeline` is a pure
  function over `[MemoryNote]`; keep it as `enum KnowledgeTimeline`, regrouped by
  parent.
- `SessionDiagnostics` — about 12 sites plus `Views/HistorySessionDiagnostics.swift`
  in full.
- `prettyJSON` export — 4 sites; becomes "Copiar Markdown", so the export and the
  durable copy are the same bytes.
- `MeetingRecording` — paths move into `raw/`; `preferredURL` collapses from four
  probe locations to one, and the `.caf` plus
  `~/Library/Application Support/CueMe/recordings/<uuid>/` fallbacks are deleted.
- Attachments — `AppModel+MemoryNotes.swift` copies into `raw/attachments/` and
  stores that relative path.
- Sidebar tree and masthead — `ProjectTreeRows`, `ProjectTreeSupport`,
  `NoteListProjection`, `LibraryColumns`, `RootWorkspaceShell`, `NoteMasthead`,
  `NoteMastheadModel`.
- Semantic index — **chunk ids do not change**; every one derives from a domain
  UUID that survives. Only the project filter disappears and `tags` joins the
  content chunk.
- `UITestFixtures` — including `semanticIndexURL`, which currently points inside
  what becomes the bundle root and must move out.

---

## 10. Risks

1. **`MemoryNote: Equatable` by id only.** A naive round-trip assertion passes
   vacuously. `assertDeepEqual` (T009) must exist before the first round-trip test.
2. **`.notLoaded` erasing a transcript.** The most destructive failure available
   here. Mitigated by the type; the test asserts bytes, not counts.
3. **A note is two filesystem objects.** Mitigated by ordered move with rollback
   and by orphan folders keeping their children (T013 AC2, T015 AC2).
4. **Rename moves a file and rewrites N links.** Only an explicit user rename moves
   anything. Partial failure leaves mixed links — tolerable, since OKF requires
   tolerating broken links and resolution is by UUID, but it must be reported.
5. **Yams under Swift 6 strict concurrency.** `Node` and `Emitter` are not
   `Sendable`. Confine them to non-escaping synchronous calls; never store a `Node`
   on a model type. Yams is libyaml-backed C — validate the signed DMG in T002, not
   at release.
6. **The inline comments are ugly in a raw editor.** The honest price of
   losslessness in Markdown.
7. **No schema discriminator for `x_cueme_*`.** The greenfield policy forbids an
   in-app migration, so the next format change is another one-shot script. Say it
   out loud in ADR 0046 so it is a decision rather than a surprise.
8. **Deep hierarchies make long paths.** No artificial limit; if `PATH_MAX` is hit
   the I/O error is already clear.

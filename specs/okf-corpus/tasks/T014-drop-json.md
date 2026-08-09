---
id: T014
title: Deletar session.json e o export JSON
depends_on: [T013]
branch: felipe/okf-T014-drop-json
commit: "feat!: delete session.json and the JSON export"
size: M
---

## Objetivo

O `.md` passa a ser a única cópia durável. Some `session.json`, somem os
encoders/decoders que existiam para ele, some o export JSON — substituído por
"Copiar Markdown", que faz do export e da cópia durável os mesmos bytes.

Aqui também morrem os testes de decode tolerante: sem JSON, eles não testam nada.

## Escopo

### PODE TOCAR
- `CueMe/Model/CorpusStore.swift` — parar de escrever JSON
- `CueMe/Model/SessionArchive.swift` — remover encoder, decoder e o write
- `CueMe/Model/MemoryNote.swift` — remover `prettyJSON` e `exportFilename`
- `CueMe/Views/HistoryExportToolbar.swift`, `NoteWorkspaceHeaderBar.swift`,
  `HistoryView.swift` — "Copiar Markdown"
- `CueMeTests/SessionRecordTests.swift` — apagar os testes de decode legado;
  preservar o de correção de `TranscriptLine` movendo-o para o suite de round-trip
- `CueMeTests/SemanticMemoryIndexTests.swift` — o decode legado de `SessionTakeaway`
- `docs/adr/0046-note-corpus-is-an-okf-bundle.md` — novo
- `docs/adr/README.md`

### NÃO PODE TOCAR
- `CueMe/Model/OKF/**`
- `projectID` / `personIDs` — é T016

## Contexto obrigatório

- `specs/okf-corpus/design.md` §2 (as quatro regras), §3 (mapeamentos rejeitados) —
  o ADR 0046 tem que registrar os dois, para ninguém relitigar.
- `CueMe/Model/MemoryNote.swift:273-285` — `prettyJSON` e `exportFilename`.
- `CueMeTests/SessionRecordTests.swift` — separe o que é decode legado do que é
  comportamento real antes de apagar.

## Decisões já tomadas

- **ADR 0046** é o ADR grande: layout, reservados, `type`, `okf_version` só na raiz,
  as quatro regras, split frontmatter/corpo, namespace `x_cueme_*`, evidência →
  `sources` + footnotes, regra de escape, marcadores em inglês com títulos em
  pt-BR, e a lista explícita de mapeamentos nativos **rejeitados**. **Supersede o
  ADR 0031.**
- O ADR precisa dizer em voz alta: não existe discriminador de versão para
  `x_cueme_*`, então a próxima quebra de formato será outro script one-shot. Isso é
  decisão, não descuido.
- "Copiar JSON" some. É remoção visível ao usuário e vai nas release notes.

## Critérios de aceite (EARS)

- **AC1** — QUANDO uma nota é salva, O SISTEMA DEVE não criar `session.json`.
- **AC2** — QUANDO o usuário exporta uma nota, O SISTEMA DEVE entregar exatamente os
  bytes do `.md` dela.
- **AC3** — QUANDO um corpus contém um `session.json` remanescente, O SISTEMA DEVE
  ignorá-lo — nem ler, nem apagar.
- **AC4** — QUANDO `grep -rn "session.json\|prettyJSON\|exportFilename" CueMe/` roda,
  O SISTEMA DEVE não retornar nada.
- **AC5** — QUANDO uma correção de `TranscriptLine` é aplicada, O SISTEMA DEVE
  preservar `originalText` e `editedAt` — o comportamento que o teste legado cobria
  segue coberto.

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testSaveWritesNoJSON` | `CueMeTests/CorpusStoreTests.swift` | AC1 |
| `testExportIsTheNoteMarkdown` | `CueMeTests/NoteExportTests.swift` | AC2 |
| `testStraySessionJSONIsIgnored` | `CorpusStoreTests` | AC3 |
| `testCorrectionKeepsAuditTrail` | `CueMeTests/NoteDocumentRoundTripTests.swift` | AC5 |

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] Nenhum caminho do app escreve ou lê JSON de nota
- [ ] ADR 0046 escrito, indexado, e supersede 0031 explicitamente
- [ ] Testes legados apagados; o comportamento real que eles cobriam continua coberto
- [ ] Os ACs com teste nomeado, cada um visto falhar antes
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

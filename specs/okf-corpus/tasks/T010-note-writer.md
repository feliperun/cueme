---
id: T010
title: NoteDocumentWriter
depends_on: [T003, T004, T005, T006, T009]
branch: felipe/okf-T010-note-writer
commit: "feat(okf): write note markdown as an OKF concept doc"
size: L
---

## Objetivo

Transformar um `MemoryNote` no documento OKF definido em
`contracts/note.md` — byte a byte. Este é o lado da escrita do contrato; o golden
é a especificação executável.

Ainda não é ligado a `SessionStore`: a tarefa entrega a função e a prova.

## Escopo

### PODE TOCAR
- `CueMe/Model/OKF/NoteDocumentWriter.swift` — novo
- `CueMe/Model/CueMeProducer.swift` — novo, minúsculo
- `CueMeTests/NoteDocumentWriterTests.swift` — novo
- `CueMeTests/Fixtures/RichNote.swift` — novo, a fixture que corresponde ao golden

### NÃO PODE TOCAR
- `CueMe/Model/SessionArchive.swift` — a troca é T013
- `CueMe/Model/OKF/NoteDocumentReader.swift` — é T012
- `specs/okf-corpus/contracts/note.md` — **o golden é a especificação.** Se o writer
  não consegue produzi-lo, isso é um stop-and-report, não um motivo para editar o
  golden.

## Contexto obrigatório

- `specs/okf-corpus/contracts/note.md` — o alvo. Leia byte a byte.
- `specs/okf-corpus/design.md` §3 (ordem de chaves, omissões, política de aspas),
  §4.1 a §4.10 (ordem das seções e cada gramática).
- `CueMe/Model/SessionArchive.swift:12-166` — o writer atual, para saber o que sai.

## Decisões já tomadas

- `CueMeProducer.current` é `cueme/<CFBundleShortVersionString>` e é **injetável**,
  para o teste pinar `cueme/test` como no golden.
- Seções vazias não são emitidas.
- Dicionários, tags e keyterms saem ordenados por chave.
- `sources` sai ordenado por `id`; `notes` sai ordenado por `timeOffset`.
- A seção `sources` é derivada de `sources[]` do frontmatter — ela renderiza as
  definições de footnote para qualquer renderizador Markdown resolver `[^ev-…]`.
- Não há mais lista de metadados (`- Data:`, `- Duração:`, `- Modo:`) sob o H1, e
  não há mais seção de integridade no corpo: os dois eram renderizações de campos
  que agora vivem no frontmatter, e emiti-los violaria a regra 2.

## Critérios de aceite (EARS)

- **AC1** — QUANDO a fixture rica é escrita com `producer: "cueme/test"`, O SISTEMA
  DEVE produzir exatamente os bytes de `contracts/note.md`.
- **AC2** — QUANDO a transcrição está `.notLoaded(turns: 2)`, O SISTEMA DEVE emitir
  `x_cueme_transcript.turns: 2` corretamente, sem carregar nada.
- **AC3** — QUANDO a nota é escrita à mão (sem sessão, sem ata, sem pendências),
  O SISTEMA DEVE produzir um arquivo com **zero** ocorrência de `cueme:`.
- **AC4** — QUANDO um campo opcional está vazio, O SISTEMA DEVE omitir a chave
  inteira do frontmatter, não emitir `null` nem lista vazia.
- **AC5** — QUANDO a nota tem `unknownFrontmatterYAML`, O SISTEMA DEVE reemiti-lo
  literal, depois de todas as chaves conhecidas.
- **AC6** — QUANDO a nota tem `residualMarkdown`, O SISTEMA DEVE reemiti-lo no fim
  do corpo.
- **AC7** — QUANDO um texto livre contém uma linha `<!-- cueme:minutes -->`,
  O SISTEMA DEVE escapá-la.
- **AC8** — QUANDO a mesma nota é escrita duas vezes, O SISTEMA DEVE produzir bytes
  idênticos.

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testWritesTheGoldenNoteByteForByte` | `NoteDocumentWriterTests` | AC1 |
| `testEmitsTurnCountWithoutLoadingTheTranscript` | idem | AC2 |
| `testPlainNoteHasNoMachineMarkers` | idem | AC3 |
| `testOmitsEmptyOptionalKeys` | idem | AC4 |
| `testReemitsUnknownFrontmatterLast` | idem | AC5 |
| `testReemitsResidualAtTheEnd` | idem | AC6 |
| `testEscapesMarkerLookalikesInFreeText` | idem | AC7 |
| `testWritingTwiceIsByteIdentical` | idem | AC8 |

AC1 lê o golden do disco e compara com `XCTAssertEqual` de string inteira. Em
falha, imprima o **primeiro** índice divergente e as duas linhas — comparar 120
linhas no olho é inviável.

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] O golden é reproduzido byte a byte, sem edições no golden
- [ ] `RichNote` fixture corresponde exatamente aos ids e datas do golden
- [ ] Os 8 ACs com teste nomeado, cada um visto falhar antes
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

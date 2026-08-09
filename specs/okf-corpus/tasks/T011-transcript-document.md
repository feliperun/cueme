---
id: T011
title: TranscriptDocument
depends_on: [T003, T004, T005, T006, T009]
branch: felipe/okf-T011-transcript-document
commit: "feat(okf): write and read raw/transcript.md"
size: M
---

## Objetivo

A transcrição vira um documento OKF próprio, em `raw/`, com `type: Transcript`.
É captura, não conceito — separá-la é o que mantém o `.md` da nota em tamanho
humano e o que torna barato o snapshot durante uma sessão ao vivo.

**A parte mais importante desta tarefa é o AC1.** Salvar uma nota cuja transcrição
não foi carregada não pode tocar o arquivo. É a falha mais destrutiva disponível em
todo o plano.

## Escopo

### PODE TOCAR
- `CueMe/Model/OKF/TranscriptDocument.swift` — novo
- `CueMeTests/TranscriptDocumentTests.swift` — novo

### NÃO PODE TOCAR
- `CueMe/Model/OKF/NoteDocumentWriter.swift` — é T010
- `CueMe/Model/CorpusStore.swift` — é T013
- `specs/okf-corpus/contracts/transcript.md` — o golden é a especificação

## Contexto obrigatório

- `specs/okf-corpus/contracts/transcript.md` — o alvo, byte a byte.
- `specs/okf-corpus/design.md` §4.11 (gramática E) e §7 (`TranscriptState`).
- `CueMe/Model/Types.swift:58-100` — `TranscriptLine`, incluindo a trilha de
  auditoria `originalText` / `editedAt`.

## Superfície

```swift
enum TranscriptDocument {
    /// `nil` quando `note.transcript` é `.notLoaded` — o chamador não deve escrever nada.
    static func write(_ note: MemoryNote, producer: String = CueMeProducer.current) -> String?

    static func read(_ markdown: String) -> [TranscriptLine]

    /// Blocos de turno só, sem frontmatter — para o append incremental de T019.
    static func renderTurns(_ lines: [TranscriptLine], startedAt: Date, participantNames: [Speaker: String]) -> String
}
```

## Decisões já tomadas

- Só turnos finais são escritos. `isFinal` é sempre `true` na leitura. Perder os
  parciais é uma regressão real e pequena, registrada no design §6.
- O nome em negrito e o relógio são **renderizações**: o speaker vem de `sp` e o
  tempo de `ts`. Não parseie nenhum dos dois.
- `orig` e `tr` carregam o payload **sem decoração** — nada de `_itálico_`, porque a
  regra 3 proíbe transformação que precise ser invertida exatamente.
- `renderTurns` existe agora para que T019 possa anexar sem duplicar a gramática.

## Critérios de aceite (EARS)

- **AC1** — QUANDO a transcrição está `.notLoaded` e a nota é salva, O SISTEMA DEVE
  devolver `nil` e o arquivo em disco DEVE ficar **byte a byte** idêntico.
- **AC2** — QUANDO um turno tem `originalText` e `editedAt`, O SISTEMA DEVE
  round-tripar a trilha de auditoria.
- **AC3** — QUANDO 600 turnos são escritos e relidos, O SISTEMA DEVE devolver os 600
  com `ts` preservado no milissegundo.
- **AC4** — QUANDO a fixture do golden é escrita, O SISTEMA DEVE produzir exatamente
  os bytes de `contracts/transcript.md`.
- **AC5** — QUANDO o texto de um turno contém uma linha começando com
  `<!--cueme:tr-->`, O SISTEMA DEVE escapá-la e recuperá-la intacta.
- **AC6** — QUANDO `renderTurns` produz os blocos de N turnos, O SISTEMA DEVE gerar
  exatamente o mesmo trecho que `write` gera para os mesmos N turnos.

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testNotLoadedLeavesTheFileByteIdentical` | `TranscriptDocumentTests` | AC1 |
| `testRoundTripsCorrectionAuditTrail` | idem | AC2 |
| `testRoundTripsSixHundredTurns` | idem | AC3 |
| `testWritesTheGoldenTranscriptByteForByte` | idem | AC4 |
| `testEscapesMarkerLookalikeInTurnText` | idem | AC5 |
| `testRenderTurnsMatchesFullRender` | idem | AC6 |

AC1 escreve um arquivo real numa pasta temporária, guarda os bytes, salva uma nota
com `.notLoaded`, e compara os bytes. **Não** conte turnos — compare os bytes.

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] `write` devolve `nil` em `.notLoaded` — verificado por bytes, não por contagem
- [ ] Golden reproduzido byte a byte, sem editar o golden
- [ ] Os 6 ACs com teste nomeado, cada um visto falhar antes
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

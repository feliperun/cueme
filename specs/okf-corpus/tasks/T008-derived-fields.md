---
id: T008
title: Deletar campos derivados e quantizar confidence
depends_on: [T007]
branch: felipe/okf-T008-derived-fields
commit: "refactor(model): delete summaryBullets and derived note fields"
size: M
---

## Objetivo

Tirar do modelo durável quatro campos que não carregam estado próprio, antes de o
formato em disco existir — assim eles nunca chegam a ser escritos em Markdown. E
quantizar `confidence` no domínio, o que torna a idempotência do round-trip
independente da formatação de float do emitter.

## Escopo

### PODE TOCAR
- `CueMe/Model/MemoryNote.swift` — remover `summaryBullets`, `schemaVersion`
- `CueMe/Model/SessionMemory.swift` — remover `createdInSessionID` de
  `SessionTakeaway` e `MeetingReviewItem`; quantizar `confidence`
- `CueMe/Model/AppModel+SessionMemory.swift` — os dois leitores e `enriched(_:record:)`
- `CueMe/Model/SessionCoordinator.swift` — onde `summaryBullets` era derivado
- `CueMe/Brain/SessionMemoryDigest.swift` — o ramo `else if !record.summaryBullets`
- `CueMe/Model/MemoryEvidenceLinker.swift` — quantização na origem
- `CueMe/Model/UITestFixtures.swift`
- Testes que constroem esses campos

### NÃO PODE TOCAR
- `CueMe/Model/OKF/**`
- `relativeFolderPath` e `archiveFolderName` — saem em T013/T016, junto com a árvore

## Contexto obrigatório

- `specs/okf-corpus/design.md` §6 — a tabela de deletados e o porquê de cada um.
- `CueMe/Model/AppModel+SessionMemory.swift:144,156` — os únicos dois leitores de
  `summaryBullets`, ambos `summaryBullets.first ?? title`.
- `CueMe/Model/SessionCoordinator.swift:1037` e
  `AppModel+SessionMemory.swift:412,422` — onde ele é derivado de `minutes.topics`.

## Decisões já tomadas

- `summaryBullets` é projeção pura de `minutes.topics`. Os dois leitores passam a
  `record.minutes.topics.first.map { "\($0.title): \($0.summary)" } ?? record.title`.
  Apagá-lo também elimina o ramo `else` de `SessionMemoryDigest` que hoje só é
  alcançado quando não há tópicos.
- `schemaVersion` é escrito e nunca ramificado. Sai. O corpus não ganha
  discriminador de versão — a próxima quebra de formato será outro script one-shot,
  e isso está registrado no ADR 0046.
- `createdInSessionID` é sempre o id da nota que contém o item. Vira derivado.
- `confidence` é quantizado a **3 casas** no momento da atribuição, não na
  serialização.

## Critérios de aceite (EARS)

- **AC1** — QUANDO um `confidence` é atribuído com mais de 3 casas, O SISTEMA DEVE
  armazená-lo já quantizado.
- **AC2** — QUANDO a UI pede o resumo curto de uma nota, O SISTEMA DEVE derivá-lo de
  `minutes.topics` sem nenhum campo intermediário.
- **AC3** — QUANDO uma nota não tem tópicos, O SISTEMA DEVE cair no título, como
  antes.
- **AC4** — QUANDO um takeaway ou item de review é lido, O SISTEMA DEVE expor a
  sessão de origem derivada do id da nota que o contém.
- **AC5** — QUANDO `grep -rn "summaryBullets\|schemaVersion\|createdInSessionID" CueMe/`
  roda, O SISTEMA DEVE não retornar nada.

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testConfidenceIsQuantizedOnAssignment` | `CueMeTests/MemoryNoteTests.swift` | AC1 |
| `testShortSummaryComesFromMinutesTopics` | `CueMeTests/SessionPostProcessorTests.swift` | AC2 |
| `testShortSummaryFallsBackToTitle` | idem | AC3 |
| `testOriginSessionIsDerivedFromTheContainingNote` | `CueMeTests/MemoryNoteTests.swift` | AC4 |

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] Os quatro campos removidos; nenhum call site órfão
- [ ] Quantização na atribuição, não na escrita
- [ ] Os ACs com teste nomeado, cada um visto falhar antes
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

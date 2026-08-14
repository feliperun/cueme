---
id: T017
title: Aninhar nota por arrastar e soltar
depends_on: [T016]
branch: felipe/okf-T017-drag-nesting
commit: "feat(library): nest notes by drag and drop"
size: L
---

## Objetivo

A hierarquia vira manipulável direto na barra lateral, estilo Notion: arrastar uma
nota sobre outra a move para dentro dela e cria a pasta. É a affordance que torna a
"entidade única" utilizável — sem ela, o usuário só consegue organizar mexendo no
Finder.

## Escopo

### PODE TOCAR
- `CueMe/Views/ProjectTreeRows.swift` → renomear para `NoteTreeRows.swift`
- `CueMe/Views/ProjectTreeSupport.swift` → `NoteTreeSupport.swift`
- `CueMe/Views/RootWorkspaceShell.swift`, `LibraryColumns.swift`
- `CueMe/Model/AppModel+MemoryNotes.swift` — a ação de mover
- `CueMeTests/NoteTreeProjectionTests.swift`
- `CueMeTests/NoteDropTargetTests.swift` — novo

### NÃO PODE TOCAR
- `CueMe/Model/CorpusStore.swift` — `move` já existe desde T015
- `CueMe/Model/OKF/**`

## Contexto obrigatório

- `CueMe/Views/ProjectTreeRows.swift` — como as linhas são construídas hoje e quais
  identificadores de acessibilidade já existem.
- T015 — `CorpusStore.move(_:under:)` e as regras de destino inválido. Não
  reimplemente validação; chame a que existe.
- `AGENTS.md` §"End-to-end tests" — esta é uma mudança visível num fluxo primário,
  então o cenário E2E é obrigatório. Ele é escrito em T021; aqui garanta os
  identificadores estáveis de que ele vai precisar.

## Decisões já tomadas

- Soltar A sobre B move A para dentro de B. Soltar na raiz desaninha.
- Destino inválido (mover um pai para dentro do próprio descendente, ou soltar sobre
  si mesmo) recebe feedback visual e é recusado.
- A validação de destino é **a mesma** de T015. Sem regra duplicada na view.
- Falha em disco reverte a UI e avisa o usuário — nunca deixa a árvore mostrando um
  estado que o filesystem não tem.
- Toda a lógica testável (pode soltar? qual é o destino? qual a nova ordem?) vive num
  tipo puro em `NoteTreeSupport`, não dentro do modificador de drop. É isso que
  torna os ACs testáveis sem UI test.

## Critérios de aceite (EARS)

- **AC1** — QUANDO o usuário solta uma nota sobre outra, O SISTEMA DEVE movê-la para
  dentro e persistir imediatamente.
- **AC2** — QUANDO o usuário tenta soltar um pai dentro do próprio descendente,
  O SISTEMA DEVE recusar e sinalizar destino inválido.
- **AC3** — QUANDO a nota arrastada tem subárvore, O SISTEMA DEVE mover tudo junto.
- **AC4** — QUANDO o move falha em disco, O SISTEMA DEVE reverter a UI e avisar.
- **AC5** — QUANDO o usuário solta uma nota na raiz, O SISTEMA DEVE desaninhá-la.
- **AC6** — QUANDO uma nota é solta sobre si mesma, O SISTEMA DEVE não fazer nada.
- **AC7** — QUANDO a árvore é renderizada, O SISTEMA DEVE dar a cada linha um
  identificador de acessibilidade estável derivado do id da nota.

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testDropOnNoteMovesItUnderTheTarget` | `NoteDropTargetTests` | AC1 |
| `testRejectsDropIntoOwnDescendant` | idem | AC2 |
| `testMovingCarriesTheSubtree` | idem | AC3 |
| `testFailedMoveRevertsTheProjection` | idem | AC4 |
| `testDropOnRootUnnests` | idem | AC5 |
| `testDropOnSelfIsANoOp` | idem | AC6 |
| `testRowsExposeStableIdentifiers` | `NoteTreeProjectionTests` | AC7 |

Todos testáveis sem UI test, porque a decisão vive num tipo puro.

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

A suíte de UI **não** roda aqui. O cenário E2E é T021 e o job `ui-e2e` do CI é o gate.

## Definition of done

- [ ] Decisão de drop num tipo puro, testada sem UI test
- [ ] Validação de destino reaproveitada de T015, não reescrita
- [ ] Identificadores de acessibilidade estáveis para o E2E de T021 usar
- [ ] Os 7 ACs com teste nomeado, cada um visto falhar antes
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

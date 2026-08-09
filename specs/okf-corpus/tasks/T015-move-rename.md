---
id: T015
title: Mover e renomear nota, reescrevendo links de entrada
depends_on: [T014]
branch: felipe/okf-T015-move-rename
commit: "feat(okf): move and rename notes, rewriting inbound links"
size: L
---

## Objetivo

Uma nota é dois objetos no filesystem: `<slug>.md` e, condicionalmente, `<slug>/`.
Mover e renomear precisam levar os dois, sem deixar meio estado se algo falhar. E
como o path é a hierarquia, renomear muda caminhos — então os links de entrada
precisam ser reescritos, senão o corpus aberto no Obsidian fica cheio de link morto.

## Escopo

### PODE TOCAR
- `CueMe/Model/CorpusStore.swift` — `move`, `rename`
- `CueMe/Model/NoteTree.swift` — validação de destino
- `CueMe/Model/OKF/BacklinkIndex.swift` — novo
- `CueMeTests/CorpusMoveRenameTests.swift` — novo
- `CueMeTests/BacklinkIndexTests.swift` — novo

### NÃO PODE TOCAR
- UI — arrastar e soltar é T017
- `projectID` / `personIDs` — é T016

## Contexto obrigatório

- `specs/okf-corpus/design.md` §1 (slug segue rename explícito) e §8 ("o invariante
  dos dois objetos").
- `specs/okf-corpus/contracts/log.md` — os rótulos `**Movimentação**` e
  `**Renomeação**`, e o que merece entrada no log.

## Superfície

```swift
extension CorpusStore {
    static func move(_ note: MemoryNote, under parent: MemoryNote?) -> MemoryNote?
    static func rename(_ note: MemoryNote, to title: String) -> MemoryNote?
}

enum BacklinkIndex {
    static func references(to path: String, in root: URL) -> [URL]
    @discardableResult
    static func rewrite(from old: String, to new: String, in root: URL) -> Int
}
```

## Decisões já tomadas

- Ordem do move: **pasta primeiro, arquivo depois.** Se o segundo passo falhar,
  reverta o primeiro e deixe o disco no estado original.
- Colisão de slug no destino resolve com `-2`, `-3`, dentro do diretório de destino.
- **Só rename explícito do usuário move arquivo** (`titleSource == .user`). Título
  gerado por IA muda durante o pós-processamento e não pode causar churn de arquivo
  nem reescrita de links.
- `BacklinkIndex.rewrite` troca links de corpo `](/old.md)` e os paths em
  `x_cueme_links` e `sources[].resource`. É best-effort: resolução é por UUID, então
  link quebrado é degradação de portabilidade, não bug de correção — mas o resultado
  tem que ser **relatado no log**, nunca silencioso.
- Mover um pai para dentro do próprio descendente é inválido e recusado.

## Critérios de aceite (EARS)

- **AC1** — QUANDO uma nota com filhas é movida, O SISTEMA DEVE levar a subárvore
  inteira e o `raw/`.
- **AC2** — QUANDO o segundo passo do move falha, O SISTEMA DEVE reverter o primeiro
  e deixar o disco exatamente como estava.
- **AC3** — QUANDO uma nota é renomeada, O SISTEMA DEVE reescrever os links de
  entrada no corpo e no frontmatter das notas que a citam, e registrar quantas
  páginas mudaram.
- **AC4** — QUANDO um link aponta para uma página inexistente, O SISTEMA DEVE
  tolerar sem erro.
- **AC5** — QUANDO o título vem de geração por IA, O SISTEMA DEVE **não** renomear o
  arquivo.
- **AC6** — QUANDO se tenta mover um pai para dentro do próprio descendente,
  O SISTEMA DEVE recusar e não tocar o disco.
- **AC7** — QUANDO o destino já tem um slug igual, O SISTEMA DEVE desambiguar.
- **AC8** — QUANDO um move ou rename termina, O SISTEMA DEVE acrescentar uma entrada
  ao `log.md`.

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testMovingCarriesTheWholeSubtree` | `CorpusMoveRenameTests` | AC1 |
| `testFailedSecondStepRollsBack` | idem | AC2 |
| `testRenameRewritesInboundLinks` | `BacklinkIndexTests` | AC3 |
| `testBrokenLinkIsTolerated` | idem | AC4 |
| `testGeneratedTitleDoesNotMoveTheFile` | `CorpusMoveRenameTests` | AC5 |
| `testCannotMoveAParentIntoItsOwnChild` | idem | AC6 |
| `testDestinationSlugCollisionIsDisambiguated` | idem | AC7 |
| `testMoveAndRenameAreLogged` | idem | AC8 |

AC2 exige injetar a falha — um protocolo fino de filesystem, ou um destino não
gravável criado no teste. Não pule este AC: é a diferença entre uma inconsistência
recuperável e perder a subárvore.

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] Move é ordenado e reverte de verdade — provado por teste, não por leitura
- [ ] `rewrite` cobre corpo, `x_cueme_links` e `sources[].resource`
- [ ] Os 8 ACs com teste nomeado, cada um visto falhar antes
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

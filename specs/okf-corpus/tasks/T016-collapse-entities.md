---
id: T016
title: Colapsar projetos e pessoas em notas
depends_on: [T015]
branch: felipe/okf-T016-collapse-entities
commit: "feat!: collapse projects and people into notes"
size: L
---

## Objetivo

A tarefa central. Depois dela existe **uma entidade só**: a nota. Projeto é uma
nota. Pessoa é uma nota. Área é uma nota. Sobram exatamente duas relações:
hierarquia (o path) e link (sem tipo).

Isso apaga um catálogo JSON, dois tipos de domínio, dois campos do modelo, um store
inteiro e o conceito de `_Inbox` — e mata de vez o bug em que trocar de projeto
movia a pasta e invalidava URLs de áudio abertas.

## Escopo

### PODE TOCAR
- `CueMe/Model/MemoryNote.swift` — remover `projectID` e `personIDs`; entra
  `links: [String]`
- `CueMe/Model/KnowledgeEntities.swift` — apagar `KnowledgeProject`,
  `KnowledgePerson`, `KnowledgeEntityStore`; **preservar** `timeline` como
  `enum KnowledgeTimeline`, reagrupada por pai
- `CueMe/Model/ProjectWorkspaceStore.swift` — **deletar**
- `CueMe/Model/AppModel.swift`, `AppModel+SessionMemory.swift`,
  `AppModel+MemoryNotes.swift`, `AppModel+LibrarySearch.swift` — `assignProject`,
  `linkPerson`, `relocate`, carga do catálogo
- `CueMe/Model/MemoryChunkBuilder.swift`, `SemanticMemoryIndex.swift`,
  `SessionKnowledgeIndex.swift`, `RelevantMemoryContextBuilder.swift` — sai o filtro
  por projeto; `tags` entra no chunk de conteúdo
- `CueMe/Views/ProjectTreeRows.swift`, `ProjectTreeSupport.swift`,
  `NoteListProjection.swift`, `LibraryColumns.swift`, `RootWorkspaceShell.swift` —
  árvore de notas
- `CueMe/Views/NoteMasthead.swift`, `NoteMastheadModel.swift`,
  `NoteMetadataChips.swift` — chips de "Relacionadas"
- `CueMe/Model/UITestFixtures.swift`
- Testes afetados
- `docs/adr/0047-capture-knowledge-and-the-single-entity.md` — novo
- `docs/adr/README.md`

### NÃO PODE TOCAR
- `CueMe/Model/OKF/**` exceto onde `x_cueme_links` precisa ser lido e escrito
- Arrastar e soltar — é T017

## Contexto obrigatório

- `specs/okf-corpus/design.md` §1 ("Uma entidade", as duas relações), §6 (campos).
- `specs/okf-corpus/spec.md` — a seção de escopo, para não construir a camada
  derivada por engano.
- `CueMe/Model/KnowledgeEntities.swift:83-103` — `timeline`, que é função pura sobre
  `[MemoryNote]` e **fica**.

## Decisões já tomadas

- `x_cueme_links: [String]` guarda paths bundle-relative. **Sem tipo.** Quem é
  pessoa, quem é projeto e quem é documento se decide por onde a nota mora na
  árvore — que é a postura do OKF: link é aresta dirigida, o tipo vem do texto ao
  redor.
- Não existe mais chip de "Projeto" nem de "Participantes". Um chip só,
  "Relacionadas", navegável.
- `_Inbox` desaparece. Nota sem pai é nota na raiz; sessão nova nasce sob a nota
  `inbox`, que é uma nota comum e pode ser renomeada ou movida.
- `participantNames` **fica** — é rótulo de speaker da transcrição, não entidade.

## Critérios de aceite (EARS)

- **AC1** — QUANDO uma nota é criada dentro de outra, O SISTEMA DEVE mostrá-la
  aninhada, sem nenhum conceito de projeto envolvido.
- **AC2** — QUANDO uma nota linka outra, O SISTEMA DEVE mostrar o chip e navegar até
  ela ao clicar.
- **AC3** — QUANDO a nota alvo de um link é renomeada, O SISTEMA DEVE manter o link
  funcionando (T015 reescreve).
- **AC4** — QUANDO `grep -rn "KnowledgeProject\|KnowledgePerson\|projectID\|personIDs\|_Inbox\|assignProject\|relocate" CueMe/`
  roda, O SISTEMA DEVE não retornar nada.
- **AC5** — QUANDO a busca semântica roda, O SISTEMA DEVE devolver os mesmos ids de
  chunk de antes — nenhum id deriva de projeto.
- **AC6** — QUANDO a linha do tempo da biblioteca é montada, O SISTEMA DEVE agrupar
  por nota-pai.
- **AC7** — QUANDO `knowledge-entities.json` existe no disco, O SISTEMA DEVE
  ignorá-lo — nem ler, nem apagar.

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testChildNoteAppearsNestedInTheTree` | `CueMeTests/NoteTreeProjectionTests.swift` | AC1 |
| `testLinkChipNavigatesToTheTarget` | `CueMeTests/NoteMastheadModelTests.swift` | AC2 |
| `testRenamingATargetKeepsTheLinkAlive` | `CueMeTests/BacklinkIndexTests.swift` | AC3 |
| `testChunkIdsAreUnchanged` | `CueMeTests/SemanticMemoryIndexTests.swift` | AC5 |
| `testTimelineGroupsByParent` | `CueMeTests/KnowledgeTimelineTests.swift` | AC6 |
| `testLegacyEntityCatalogueIsIgnored` | `CueMeTests/CorpusStoreTests.swift` | AC7 |

`ProjectTreeProjectionTests.swift` vira `NoteTreeProjectionTests.swift`.

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] Os dois tipos, o store e o catálogo JSON deletados; `timeline` preservada
- [ ] ADR 0047 escrito e indexado: captura vs. conhecimento, entidade única,
      hierarquia pelo path, `TranscriptState`, perdas aceitas
- [ ] AC4 verificado por grep, colado no relatório
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

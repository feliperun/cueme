---
id: T013
title: NoteTree e CorpusStore
depends_on: [T012]
branch: felipe/okf-T013-corpus-store
commit: "feat(okf): load and save the note tree"
size: L
---

## Objetivo

Ligar o formato ao filesystem. `CorpusStore` substitui `SessionStore`: descobre a
árvore de notas, carrega só os `.md`, carrega transcrição sob demanda, e salva.

`session.json` **continua sendo escrito** nesta tarefa; a leitura é que passa a vir
do Markdown. Isso é ordenação de uma mudança de dois lados dentro do mesmo PR, não
camada de compatibilidade — T014 tira o JSON logo em seguida. Diga isso no relatório
para o revisor não sinalizar.

## Escopo

### PODE TOCAR
- `CueMe/Model/NoteTree.swift` — novo
- `CueMe/Model/CorpusStore.swift` — novo
- `CueMe/Model/SessionArchive.swift` — `SessionStore` delega para `CorpusStore`
- Call sites de `SessionStore.save/loadAll/prepareSession/archiveDirectory`
- `CueMe/Audio/MeetingRecorder.swift` — caminhos passam por `CorpusStore`
- `CueMe/Model/UITestFixtures.swift` — incluindo mover `semanticIndexURL` para
  **fora** da raiz do corpus
- Testes que usam `SessionStore.rootOverride`
- `CueMeTests/CorpusStoreTests.swift` — novo

### NÃO PODE TOCAR
- `projectID` / `personIDs` / `relocate` — a demolição é T016
- `CueMe/Model/OKF/**` — está pronto

## Contexto obrigatório

- `specs/okf-corpus/design.md` §1 (layout), §8 (superfície de `CorpusStore`,
  invariante dos dois objetos), §7 (transcrição sob demanda).
- `CueMe/Model/SessionArchive.swift:186-307` — `rootURL`, `save`, `loadArchive`.
  Repare que o discovery atual enumera a raiz inteira recursivamente atrás de
  `session.json`, entrando em `attachments/` e em qualquer pasta do usuário.

## Decisões já tomadas

- Uma nota é `<slug>.md`; a pasta irmã `<slug>/` existe **só** quando há filhos ou
  `raw/`, e é removida quando perde os dois.
- `loadNotes()` percorre a árvore recursivamente pulando nomes reservados, lê **só**
  os `.md`, e nunca entra em `raw/`.
- Pasta órfã (sem `<slug>.md` irmão) **não perde as filhas**: elas carregam
  normalmente e a inconsistência é reportada. Não sintetize uma nota-tampão.
- `rootURL` mantém a mesma chave de `UserDefaults` (`sessionArchiveRootPath`).
- Nova sessão nasce sob a nota `inbox`, que é uma nota comum criada na primeira
  execução se não existir.

## Critérios de aceite (EARS)

- **AC1** — QUANDO `loadNotes()` roda para N notas, O SISTEMA DEVE fazer N leituras
  de arquivo e **zero** leitura dentro de `raw/`.
- **AC2** — QUANDO existe `acme/` sem `acme.md`, O SISTEMA DEVE carregar as filhas
  normalmente e registrar a inconsistência.
- **AC3** — QUANDO uma nota perde a última filha e o `raw/`, O SISTEMA DEVE remover
  a pasta irmã vazia.
- **AC4** — QUANDO um `.md` sem `type` está no corpus, O SISTEMA DEVE ignorá-lo sem
  erro.
- **AC5** — QUANDO uma nota é aberta, O SISTEMA DEVE carregar a transcrição sob
  demanda e `turnCount` DEVE bater com o que o frontmatter declarava.
- **AC6** — QUANDO uma nota com filhas é deletada, O SISTEMA DEVE remover o `.md`, a
  pasta irmã e toda a subárvore.
- **AC7** — QUANDO uma nota é gravada com áudio, O SISTEMA DEVE colocá-lo em
  `<slug>/raw/`.

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testLoadReadsOnlyNoteFiles` | `CorpusStoreTests` | AC1 |
| `testOrphanFolderKeepsItsChildren` | idem | AC2 |
| `testEmptySiblingFolderIsRemoved` | idem | AC3 |
| `testForeignMarkdownIsIgnored` | idem | AC4 |
| `testTranscriptLoadsOnDemand` | idem | AC5 |
| `testDeleteRemovesTheWholeSubtree` | idem | AC6 |
| `testRecordingLandsInRaw` | `CueMeTests/AudioImportAndKnowledgeTests.swift` | AC7 |

**AC1 sem relógio.** Injete um espião de `FileManager` (ou um protocolo de leitura)
e conte chamadas. Asserção de wall-clock é flaky em CI e não prova nada.

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] Discovery é dirigido pela árvore, não uma enumeração recursiva atrás de JSON
- [ ] `semanticIndexURL` das fixtures aponta para fora do corpus
- [ ] O relatório diz explicitamente que `session.json` segue sendo escrito e por quê
- [ ] Os 7 ACs com teste nomeado, cada um visto falhar antes
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

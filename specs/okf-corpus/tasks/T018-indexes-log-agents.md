---
id: T018
title: index.md por nível, log append-only e AGENTS.md do corpus
depends_on: [T016]
branch: felipe/okf-T018-indexes-log-agents
commit: "feat(okf): emit per-level indexes, append-only log and corpus AGENTS.md"
size: M
---

## Objetivo

Os três arquivos reservados que tornam o bundle navegável sem o CueMe: `index.md`
em cada nível (descoberta progressiva da árvore), `log.md` append-only na raiz, e o
`AGENTS.md` que ensina qualquer agente a operar o corpus.

## Escopo

### PODE TOCAR
- `CueMe/Model/OKF/IndexDocument.swift` — novo
- `CueMe/Model/OKF/CorpusAgentsDocument.swift` — novo
- `CueMe/Model/CorpusStore.swift` — `writeIndexes`, `appendLog`
- `CueMeTests/IndexDocumentTests.swift` — novo
- `CueMeTests/CorpusLogTests.swift` — novo
- `docs/adr/0048-one-entity-hierarchy-by-path.md` — novo
- `docs/adr/README.md`

### NÃO PODE TOCAR
- `CueMe/Brain/ClaudeSession.swift` — ver a decisão abaixo
- `CueMe/Model/OKF/NoteDocumentWriter.swift`, `NoteDocumentReader.swift`

## Contexto obrigatório

- `specs/okf-corpus/contracts/index.md` — as duas formas e a regra de ordenação.
- `specs/okf-corpus/contracts/log.md` — append-only, rótulos, o que merece entrada.
- `specs/okf-corpus/contracts/corpus-agents.md` — o conteúdo exato do `AGENTS.md`
  que o app escreve.
- `docs/adr/0005-llm-brain-via-claude-cli.md` e `0008-coach-ux-and-context-safety.md`
  — o isolamento do `ClaudeSession`, que **não** muda aqui.

## Decisões já tomadas

- `index.md` lista **filhas diretas** ordenadas por título, com a `description` de
  cada uma depois de um travessão. Só a raiz carrega `okf_version: "0.2"`; nível
  aninhado não tem frontmatter nenhum.
- `writeIndexes` é chamado **uma vez por lote**, nunca por save, e pula a escrita
  quando os bytes renderizados não mudaram — senão o diff em git vira ruído.
- `log.md` é **append-only**. Entrada nova entra no grupo da data, criando o grupo no
  topo quando o dia é novo. O histórico anterior sai byte-idêntico. Só eventos
  estruturais duráveis: criar, mover, renomear, deletar, pasta órfã encontrada,
  migração. Edição comum não vai para o log — viraria diário de teclado.
- `AGENTS.md` é escrito **só se ausente** e **nunca sobrescrito**: o template de
  referência trata esse arquivo como schema que evolui com o usuário, e sobrescrever
  apagaria os ajustes dele.
- **Gerar o `AGENTS.md` não muda o isolamento do `ClaudeSession`.** O coach continua
  rodando de cwd vazio com `disableAllHooks`. Apontá-lo para o corpus é decisão
  futura e precisa de ADR próprio que supersede o 0008. Registre isso no ADR 0048.
- O ADR 0048 também registra INGEST / QUERY / LINT como contrato-alvo — **descritas,
  não implementadas**.

## Critérios de aceite (EARS)

- **AC1** — QUANDO duas escritas de log acontecem no mesmo dia, O SISTEMA DEVE
  produzir duas entradas no mesmo grupo e deixar todo byte anterior intacto.
- **AC2** — QUANDO `AGENTS.md` já existe na raiz, O SISTEMA DEVE não sobrescrevê-lo.
- **AC3** — QUANDO nada mudou na árvore, O SISTEMA DEVE pular a escrita do `index.md`.
- **AC4** — QUANDO um `index.md` é gerado, O SISTEMA DEVE listar as filhas diretas
  com a `description` de cada, ordenadas por título.
- **AC5** — QUANDO o `index.md` da raiz é gerado, O SISTEMA DEVE ser o **único** com
  `okf_version`.
- **AC6** — QUANDO uma nota não tem `description`, O SISTEMA DEVE listá-la só com o
  link.
- **AC7** — QUANDO uma entrada nova é de um dia mais recente, O SISTEMA DEVE criar o
  grupo no topo do arquivo.

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testSecondEntrySameDayLeavesHistoryByteIdentical` | `CorpusLogTests` | AC1 |
| `testExistingAgentsFileIsNeverOverwritten` | `CueMeTests/CorpusAgentsDocumentTests.swift` | AC2 |
| `testUnchangedIndexIsNotRewritten` | `IndexDocumentTests` | AC3 |
| `testIndexListsDirectChildrenWithDescriptions` | idem | AC4 |
| `testOnlyRootIndexCarriesOkfVersion` | idem | AC5 |
| `testChildWithoutDescriptionIsListedBare` | idem | AC6 |
| `testNewDayCreatesGroupAtTheTop` | `CorpusLogTests` | AC7 |

AC1 e AC7 exigem data injetada. AC3 verifica o mtime ou um espião de escrita, não o
conteúdo.

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] Log é append de verdade — provado por comparação de prefixo, não por contagem
- [ ] `AGENTS.md` corresponde ao golden `contracts/corpus-agents.md`
- [ ] ADR 0048 registra a entidade única, a hierarquia pelo path, o log append-only,
      as três operações como contrato-alvo, e que o isolamento do coach não mudou
- [ ] Os 7 ACs com teste nomeado, cada um visto falhar antes
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

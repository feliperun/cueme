---
id: T022
title: Documentar o corpus OKF
depends_on: [T020, T021]
branch: felipe/okf-T022-docs
commit: "docs: describe the OKF corpus"
size: S
---

## Objetivo

A documentação do repo passa a descrever o que o código faz. Hoje
`ARCHITECTURE.md` e `ABSTRACTIONS.md` descrevem `session.json`, `_Inbox`, pastas de
projeto e um catálogo de entidades — nada disso existe mais.

Sem código nesta tarefa.

## Escopo

### PODE TOCAR
- `docs/ARCHITECTURE.md`
- `docs/ABSTRACTIONS.md`
- `README.md`
- `AGENTS.md` — a seção de convenções e os "gotchas"
- `docs/adr/README.md` — conferir o índice inteiro

### NÃO PODE TOCAR
- Qualquer `.swift`, `.py` ou `.pbxproj`
- ADRs já escritos — **nunca edite um ADR ativo**; supersede

## Contexto obrigatório

- `specs/okf-corpus/spec.md` e `design.md` — a fonte da verdade a destilar.
- `docs/ARCHITECTURE.md:32,130-152` — a árvore antiga documentada.
- `docs/ABSTRACTIONS.md:47,164-165` — as abstrações antigas.
- `README.md:41` — a menção a `session.json`.

## O que muda

- **Layout do corpus**: uma entidade, `<slug>.md` mais pasta irmã sob demanda,
  `raw/` como captura, reservados, aninhamento ilimitado.
- **Fora**: `session.json`, `_Inbox`, pastas de projeto, `knowledge-entities.json`,
  `KnowledgeProject`, `KnowledgePerson`, export JSON.
- **Dentro**: OKF v0.2, `index.md` por nível, `log.md` append-only, `AGENTS.md` do
  corpus, hierarquia pelo path, links sem tipo.
- **Gotchas do `AGENTS.md`** a acrescentar:
  - O `.md` é a única cópia durável; toda gravação nova precisa de round-trip
    provado, não só de um teste de escrita.
  - `MemoryNote` é `Equatable` por id — use `assertDeepEqual` em teste de round-trip.
  - Nota é dois objetos no filesystem; mover exige os dois, na ordem certa.
  - Yams fica confinado a `CueMe/Model/OKF/`.
  - Salvar uma nota com transcrição `.notLoaded` **não** pode tocar
    `raw/transcript.md` — é o que `TranscriptState` protege.
- **Gotcha antigo a remover**: o que descreve `session.json` como fonte de verdade.

## Critérios de aceite (EARS)

- **AC1** — QUANDO `grep -rn "session.json\|_Inbox\|knowledge-entities" docs/ README.md`
  roda, O SISTEMA DEVE retornar apenas menções históricas dentro de ADRs.
- **AC2** — QUANDO alguém lê `docs/ARCHITECTURE.md`, O SISTEMA DEVE apresentar a
  árvore do corpus como ela é em disco hoje.
- **AC3** — QUANDO alguém lê `docs/adr/README.md`, O SISTEMA DEVE listar 0043 a 0049
  com o status correto e todo `superseded by` apontando para o número certo.
- **AC4** — QUANDO alguém lê `AGENTS.md`, O SISTEMA DEVE encontrar os cinco gotchas
  novos e nenhum gotcha obsoleto.

## Verificação

```bash
grep -rn "session.json\|_Inbox\|knowledge-entities" docs/ README.md AGENTS.md
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] Os quatro documentos refletem o código como ele está
- [ ] Índice de ADRs conferido de ponta a ponta
- [ ] Nenhum ADR ativo foi editado
- [ ] `sentrux check` e `sentrux gate` verdes

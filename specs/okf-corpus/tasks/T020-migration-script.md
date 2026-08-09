---
id: T020
title: Script one-shot de migração para OKF
depends_on: [T018]
branch: felipe/okf-T020-migration-script
commit: "feat(scripts): add the one-shot OKF migration"
size: L
---

## Objetivo

Levar o arquivo atual do usuário para o corpus novo. Roda **uma vez**, fora do app,
e o app não embarca nenhuma linha de código de migração — política do ADR 0043.

O dado é insubstituível. O script nunca escreve na origem e só termina com sucesso
se dois checks independentes fecharem.

## Escopo

### PODE TOCAR
- `scripts/migrate-okf.py` — novo
- `scripts/tests/test_migrate_okf.py` — novo
- `.github/workflows/quality.yml` — rodar o self-test do script
- `docs/adr/0049-one-shot-external-migration.md` — novo
- `docs/adr/README.md`

### NÃO PODE TOCAR
- Qualquer coisa em `CueMe/` — o app não ganha código de migração

## Contexto obrigatório

- `CueMe/Model/NoteDocument.swift` **na história do git** (`git show <sha>:…`), em
  especial `mergeCanonicalFields:35-59`. O script tem que **replicar essa
  precedência**: título, kind, title_source, project_id, labels, updated_at e o
  corpo delimitado vinham do `note.md` e venciam o JSON. Pular isso reverte
  silenciosamente toda edição externa que o usuário já fez no arquivo dele.
- `specs/okf-corpus/design.md` §1, §3, §4 — o formato de destino.
- `specs/okf-corpus/contracts/*.md` — os goldens.

## Runtime

PEP 723 inline, para rodar com `uv run` sem instalar nada:

```python
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6.0"]
# ///
```

Emitir YAML na mão arriscaria produzir algo que o Yams lê diferente — inaceitável
num script que roda uma vez sobre dado insubstituível.

## CLI

```
migrate-okf.py --source <Session Archive> --entities <knowledge-entities.json>
               --legacy-audio <recordings/> --dest <Corpus>
               [--dry-run] [--force] [--keep-diagnostics] [--verbose]
```

Invariantes: nunca escreve em `--source`; recusa `--dest` não-vazio sem `--force`;
totalmente re-executável; exit 0 só se o verify passar.

## Mapeamento

- Cada `KnowledgeProject` → nota na raiz (`<slug>.md` + `<slug>/`), corpo = o
  `summary`, com as sessões daquele projeto como filhas.
- Cada `KnowledgePerson` → nota sob `pessoas/`, com aliases, papel e organização
  como lista no corpo.
- `personIDs` de uma nota → `x_cueme_links` apontando para as notas de pessoa.
- `personID` referenciado mas ausente do catálogo → stub
  `pessoas/pessoa-<uuid8>.md` com `x_cueme_orphan: true`. Nenhum link fica pendurado.
- Sessão sem projeto → filha de `inbox`.
- `self.m4a` / `other.m4a` / `*.caf` / `attachments/**` → `<slug>/raw/`, com
  `NoteAttachment.filename` reescrito para `raw/attachments/<nome>`.
- `--legacy-audio/<uuid>/` varrido para o `raw/` da nota correspondente.
- `diagnostics.events` descartado; `recoveries` e `errors` contados para
  `x_cueme_integrity`. Com `--keep-diagnostics`, os eventos crus vão para fora do
  bundle.
- Descartar `schemaVersion`, `relativeFolderPath`, `archiveFolderName`,
  `summaryBullets`, `createdInSessionID`; quantizar `confidence` a 3 casas.
- `MemoryEvidence` → `sources[]` apontando para `raw/transcript.md#t-<uuid>`.
- Gerar os `index.md`, o `log.md` com uma entrada `**Migração**`, e o `AGENTS.md`.
- Apagar `Memory/memory.sqlite3{,-wal,-shm}` — índice derivado, reconstrói na
  primeira busca.

## Verify

Dois checks independentes, os dois obrigatórios:

1. **Re-read** — parseia cada `.md` escrito com um `parse_note_md()` que espelha o
   contrato do reader Swift, e compara campo a campo por **lista explícita**. Nunca
   `==` de dicionário: um campo novo tem que falhar alto, não passar silencioso.
2. **Reconciliação de contagem** — lido → escrito → relido, iguais nos três, para:
   notas, turnos, pendências, decisões, questões, anotações, artefatos, tópicos,
   evidências distintas, arquivos de anexo e bytes totais de anexo.

Saída nos dois modos: tabela por entidade, o que foi descartado, áudio legado
absorvido, e a linha final `RESULT: OK — 0 mismatches`.

## Critérios de aceite (EARS)

- **AC1** — QUANDO `--dry-run` roda, O SISTEMA DEVE não escrever nada e ainda assim
  rodar os dois checks.
- **AC2** — QUANDO a origem tem um `note.md` editado por fora, O SISTEMA DEVE
  preservar a edição, não o valor do JSON.
- **AC3** — QUANDO qualquer contagem diverge, O SISTEMA DEVE sair com código ≠ 0.
- **AC4** — QUANDO roda duas vezes contra o mesmo `--dest` com `--force`, O SISTEMA
  DEVE produzir resultado idêntico.
- **AC5** — QUANDO uma sessão tinha projeto, O SISTEMA DEVE colocá-la dentro da nota
  daquele projeto.
- **AC6** — QUANDO um `personID` não existe no catálogo, O SISTEMA DEVE criar o stub
  órfão e ainda assim linkar.
- **AC7** — QUANDO `--dest` não está vazio e `--force` não foi passado, O SISTEMA
  DEVE recusar sem escrever.
- **AC8** — QUANDO a migração termina, O SISTEMA DEVE não ter tocado em nenhum byte
  de `--source`.

## Testes (TDD, red primeiro)

`scripts/tests/test_migrate_okf.py`, pytest, contra uma árvore antiga **sintética**
montada pelo próprio teste. Um teste por AC, com os nomes acima em snake_case.

AC8 tira um hash recursivo de `--source` antes e depois e compara.

## Verificação

```bash
uv run scripts/tests/test_migrate_okf.py     # ou: uv run pytest scripts/tests
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
sentrux check . && sentrux gate .
```

**Nunca rode o script contra o arquivo real do usuário.** Isso é do orquestrador, e
só com `--dry-run` primeiro.

## Definition of done

- [ ] A precedência do `note.md` sobre o JSON está replicada e testada (AC2)
- [ ] Os dois checks de verify implementados; nenhum usa `==` de dicionário
- [ ] Self-test no CI
- [ ] ADR 0049 escrito, incluindo a consequência honesta: quem não rodar o script
      abre um corpus vazio com a árvore antiga intacta ao lado — e isso vai nas
      release notes
- [ ] Os 8 ACs com teste nomeado, cada um visto falhar antes

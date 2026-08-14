---
id: T001
title: Renumerar o ADR de política greenfield para 0043
depends_on: []
branch: felipe/okf-corpus
commit: "feat!: rename SessionRecord to MemoryNote and adopt greenfield policy"
size: S
status: done
---

## Objetivo

Resolver a colisão de numeração: `main` já tem
`0038-latest-coach-cue-and-pinned-review.md`, e o ADR de política greenfield foi
escrito também como 0038. Depois desta tarefa há exatamente um ADR por número e
os ADRs desta refatoração podem ocupar 0044–0049.

## Resultado

Absorvida na resolução de conflito do rebase do commit greenfield sobre `main`.
Commitar dois ADR 0038 e corrigir em seguida seria um estado intermediário
quebrado — `docs/adr/README.md` listaria dois 0038 — sem nenhum ganho.

Feito no commit `b7d3fd8`:

- `docs/adr/0038-greenfield-compatibility-policy.md` → `0043-…` (`git mv`)
- `id: "0038"` → `id: "0043"` no frontmatter do ADR
- `docs/adr/README.md`: linha nova para 0043; `0031` passa a `superseded by 0043`
  (antes apontava para 0038, que em `main` é outro ADR)
- `AGENTS.md`: o link do `MemoryNote` aponta para 0043

## Critérios de aceite (EARS)

- **AC1** — QUANDO `ls docs/adr/` roda, O SISTEMA DEVE mostrar exatamente um
  arquivo por número. ✅
- **AC2** — QUANDO `grep -rn "0038-greenfield"` roda, O SISTEMA DEVE não retornar
  nada. ✅
- **AC3** — QUANDO o `supersedes` do ADR 0031 é lido, O SISTEMA DEVE apontar para
  0043. ✅

## Verificação

```bash
ls docs/adr/ | grep -cE '^0038' # 1
grep -rn '0038-greenfield' .    # vazio
```

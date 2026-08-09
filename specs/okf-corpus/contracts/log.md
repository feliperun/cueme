# Golden — `log.md`

One `log.md`, at the bundle root. **Append-only**: existing entries are immutable
and a new entry is inserted into its date group, creating the group at the top when
the day is new. The file is never regenerated — that is both the OKF convention and
what keeps the diff quiet when the corpus lives in git.

Dates are ISO 8601 `YYYY-MM-DD` in local time, newest group first. Each entry is a
bold operation label followed by a sentence, with bundle-relative links.

Operation labels in use: `**Criação**`, `**Atualização**`, `**Movimentação**`,
`**Renomeação**`, `**Exclusão**`, `**Migração**`, `**Inconsistência**`.

Only durable structural events are logged — creating, moving, renaming or deleting
a note, an orphan folder found at load, and the one-shot migration. Ordinary edits
are not; the file would become a keystroke journal.

```markdown
# Histórico do corpus

## 2026-08-09

- **Renomeação**: [Acme](acme.md) renomeada de `conta-acme`; 4 páginas com links atualizados.
- **Movimentação**: [Reunião 1](acme/atas/reuniao-1.md) movida para [Atas](acme/atas.md).

## 2026-08-08

- **Migração**: 214 notas importadas do arquivo anterior no formato OKF v0.2.
- **Inconsistência**: pasta `acme/orfa/` sem nota irmã; 2 filhas carregadas mesmo assim.
```

## Verification

Writing twice on the same day must produce two entries inside one group and leave
every earlier byte untouched. That is the assertion — diff the file before and
after, and require the prefix to be identical.

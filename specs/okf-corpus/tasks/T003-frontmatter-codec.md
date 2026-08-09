---
id: T003
title: OKFFrontmatter — codec YAML com preservação de chaves desconhecidas
depends_on: [T002]
branch: felipe/okf-T003-frontmatter-codec
commit: "feat(okf): add YAML frontmatter codec"
size: M
---

## Objetivo

Um codec que separa o frontmatter YAML do corpo Markdown, decodifica com Yams,
devolve as chaves conhecidas como valores tipados, e **preserva literalmente as
chaves que este build não conhece**. Preservar chave desconhecida é exigência dura
do OKF ("consumers must preserve unknown keys"); sem isso, abrir uma nota escrita
por outra ferramenta e salvar apaga metadado alheio.

Nada consome este codec ainda.

## Escopo

### PODE TOCAR
- `CueMe/Model/OKF/OKFFrontmatter.swift` — novo
- `CueMeTests/OKFFrontmatterTests.swift` — novo

### NÃO PODE TOCAR
- `CueMe/Model/MemoryNote.swift` — mapear campos é T010/T012
- `CueMe/Model/OKF/OKFSectionMarkers.swift` — corpo é T004
- Qualquer view

## Contexto obrigatório

- `specs/okf-corpus/design.md` §3 — ordem de chaves, tipos, regras de omissão e a
  **política de aspas**. A política de aspas é o que torna o teste byte-exato
  possível; não aceite o default do emitter.
- `specs/okf-corpus/contracts/note.md` — o frontmatter alvo, byte a byte.
- `CueMe/Model/NoteDocument.swift:67-114` — o parser atual, para saber o que está
  sendo substituído. Não altere esse arquivo.

## Superfície

```swift
enum OKFFrontmatter {
    /// Emite frontmatter em block style, incluindo os delimitadores `---`.
    /// A ordem do array é a ordem de saída; `unknownYAML` é anexado ao final.
    static func encode(_ ordered: [(String, OKFValue)], unknownYAML: String) -> String

    struct Parsed {
        let fields: [String: OKFValue]
        let unknownYAML: String
        let body: String
    }

    /// `nil` quando não há frontmatter, quando o YAML não parseia,
    /// ou quando `type` está ausente/vazio.
    static func decode(_ markdown: String, knownKeys: Set<String>) -> Parsed?
}
```

`OKFValue` é uma enum fechada — `string`, `int`, `double`, `bool`, `date`, `array`,
`mapping` — definida neste arquivo. Nenhum tipo do Yams pode escapar da API
pública: `Node` e `Emitter` não são `Sendable` (design §10 risco 5).

## Critérios de aceite (EARS)

- **AC1** — QUANDO o frontmatter tem uma chave fora de `knownKeys`, O SISTEMA DEVE
  devolvê-la em `unknownYAML` e reemiti-la literal, depois das chaves conhecidas.
- **AC2** — QUANDO o mesmo array ordenado é codificado duas vezes, O SISTEMA DEVE
  produzir bytes idênticos.
- **AC3** — QUANDO o documento não tem frontmatter, ou `type` está ausente ou
  vazio, O SISTEMA DEVE devolver `nil`.
- **AC4** — QUANDO um valor contém unicode, emoji, `: `, ` #` ou quebra de linha,
  O SISTEMA DEVE round-tripar sem perda.
- **AC5** — QUANDO uma data é emitida, O SISTEMA DEVE escrevê-la entre aspas
  duplas, e ao reler DEVE devolver `String`, não um timestamp YAML.
- **AC6** — QUANDO o frontmatter do golden `contracts/note.md` é decodificado e
  reemitido com a mesma ordem, O SISTEMA DEVE reproduzir o bloco byte a byte.

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testPreservesUnknownKeysVerbatim` | `OKFFrontmatterTests` | AC1 |
| `testEncodingIsDeterministic` | idem | AC2 |
| `testRejectsDocumentWithoutTypeOrFrontmatter` | idem | AC3 |
| `testRoundTripsHostileScalars` | idem | AC4 |
| `testDatesStayQuotedStrings` | idem | AC5 |
| `testReproducesGoldenFrontmatterByteForByte` | idem | AC6 |

`testRoundTripsHostileScalars` deve cobrir, no mínimo: string vazia, `"true"`,
`"42"`, `"2026-08-08"`, `"- começa com indicador"`, `"tem: dois pontos"`,
`"tem #hash"`, `" espaço na borda "`, `"multi\nlinha"`, `"emoji 🚗 e ç"`.

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] `OKFValue` fechado; nenhum tipo Yams na API pública
- [ ] Os 6 ACs com teste nomeado, cada um visto falhar antes da implementação
- [ ] AC6 lê o golden do disco; não duplique o conteúdo dentro do teste
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

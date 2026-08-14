---
id: T004
title: OKFSectionMarkers — splitter de seções e escape
depends_on: [T002]
branch: felipe/okf-T004-section-markers
commit: "feat(okf): add section marker splitter and escaping"
size: M
---

## Objetivo

O corpo Markdown passa a ser divisível em regiões identificadas por **marcador**, e
não por título. Hoje `SessionArchive.markdown` escreve `## Ata`, `## Transcrição` e
companhia sem ninguém parsear de volta; a partir daqui a identidade da seção vive
num comentário HTML na coluna 0 e o título embaixo é decoração regerada. Isso é o
que permite o usuário renomear ou reordenar títulos sem quebrar o parse.

Junto vem a regra de escape, que é o que permite escrever a string
`<!-- cueme:transcript -->` dentro de uma nota sem confundir o parser.

## Escopo

### PODE TOCAR
- `CueMe/Model/OKF/OKFSectionMarkers.swift` — novo
- `CueMeTests/OKFSectionMarkerTests.swift` — novo

### NÃO PODE TOCAR
- `CueMe/Model/SessionArchive.swift` — a substituição é T010/T013
- `CueMe/Model/OKF/OKFFrontmatter.swift` — é de T003

## Contexto obrigatório

- `specs/okf-corpus/design.md` §4.1 (estrutura e ordem canônica), §4.12 (escape),
  §5 regras 2 e 6 (residual).
- `specs/okf-corpus/contracts/note.md` — as seções reais, na ordem real.

## Superfície

```swift
enum OKFSection: String, CaseIterable {
    case minutes, takeaways, decisions, openQuestions = "open-questions"
    case followUp = "follow-up", notes, coach, artifacts, sources, transcript
}

enum OKFSectionMarkers {
    static func marker(_ section: OKFSection) -> String   // "<!-- cueme:minutes -->"

    struct Split {
        let h1: String?
        let userBody: String
        let sections: [OKFSection: String]
        let residual: String
    }
    static func split(_ body: String) -> Split

    static func escape(_ text: String) -> String
    static func unescape(_ text: String) -> String
}
```

## Regras

- Marcador é `^<!--\s?cueme:<name>\s?-->\s*$` na coluna 0.
- Uma seção vai do seu marcador até a próxima linha de marcador ou EOF. **Não há
  tag de fechamento.**
- `h1` é a primeira linha `# ` antes de qualquer marcador. `userBody` é tudo entre
  o H1 e o primeiro marcador, com as linhas em branco das bordas removidas.
- Marcador desconhecido → a região inteira, incluindo a linha do marcador, vai para
  `residual`.
- Seção repetida → concatenar as regiões na ordem em que aparecem.
- Sem nenhum marcador → `sections` vazio, `residual` vazio, tudo é `userBody`.

Escape, aplicado a toda região de texto livre:
- **escrita**: linha casando `^\\*<!--\s?cueme` ganha um `\` na frente.
- **leitura**: linha casando `^\\+<!--\s?cueme` perde um `\` da frente.

Exatamente invertível e seguro na recursão: escapar duas vezes e desescapar duas
vezes volta ao original.

## Critérios de aceite (EARS)

- **AC1** — QUANDO uma seção conhecida não está no arquivo, O SISTEMA DEVE
  devolvê-la ausente do dicionário, sem erro.
- **AC2** — QUANDO aparece um marcador desconhecido, O SISTEMA DEVE mandar a região
  inteira para `residual`.
- **AC3** — QUANDO um texto livre contém a linha `<!-- cueme:transcript -->`,
  O SISTEMA DEVE round-tripar exato, e `escape`/`unescape` DEVEM ser ponto-fixo
  também quando aplicados duas vezes.
- **AC4** — QUANDO as seções aparecem fora da ordem canônica, O SISTEMA DEVE
  parsear todas.
- **AC5** — QUANDO o corpo não tem nenhum marcador, O SISTEMA DEVE devolver tudo
  como `userBody` e nada como residual.
- **AC6** — QUANDO o corpo do golden `contracts/note.md` é dividido, O SISTEMA DEVE
  encontrar exatamente as 9 seções dele e `residual` vazio.

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testMissingSectionIsAbsentNotAnError` | `OKFSectionMarkerTests` | AC1 |
| `testUnknownMarkerRegionGoesToResidual` | idem | AC2 |
| `testEscapeIsAnExactFixedPointIncludingRepeats` | idem | AC3 |
| `testParsesSectionsOutOfOrder` | idem | AC4 |
| `testPlainNoteIsAllUserBody` | idem | AC5 |
| `testSplitsTheGoldenNoteBody` | idem | AC6 |

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] Os 6 ACs com teste nomeado, cada um visto falhar antes
- [ ] AC3 testa escape aninhado (`\<!--cueme` já escapado ganha mais um nível)
- [ ] AC6 lê o golden do disco
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

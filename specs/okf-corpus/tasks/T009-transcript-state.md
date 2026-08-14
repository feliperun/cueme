---
id: T009
title: TranscriptState e helper assertDeepEqual
depends_on: [T008]
branch: felipe/okf-T009-transcript-state
commit: "refactor(model): make the transcript a loadable state"
size: M
---

## Objetivo

Duas peças de infraestrutura que precisam existir **antes** de qualquer writer ou
reader, porque as duas previnem uma classe inteira de bug silencioso.

**`TranscriptState`** torna impossível apagar uma transcrição que você não
carregou. Quando o transcript virar arquivo separado, `loadNotes()` não vai lê-lo —
e uma nota com `transcript: []` salva por engano destruiria `raw/transcript.md`.
Fechar isso no tipo, não na disciplina.

**`assertDeepEqual`** existe porque `MemoryNote` conforma `Equatable` **só por
`id`** (`MemoryNote.swift:26-27`). Um `XCTAssertEqual(read(write(n)), n)` passa
sempre que os ids batem, independentemente de todos os outros campos. Escrito do
jeito óbvio, o teste de round-trip inteiro é vazio. Este é o jeito mais fácil de
shipar um formato quebrado com suíte verde.

## Escopo

### PODE TOCAR
- `CueMe/Model/TranscriptState.swift` — novo
- `CueMe/Model/MemoryNote.swift` — `transcript` muda de tipo
- Todo call site de `record.transcript` (use `grep -rn 'transcript' CueMe/`)
- `CueMeTests/Support/AssertDeepEqual.swift` — novo
- `CueMe/Model/UITestFixtures.swift`
- Testes afetados

### NÃO PODE TOCAR
- `CueMe/Model/OKF/**` — writers e readers são T010/T011/T012

## Contexto obrigatório

- `specs/okf-corpus/design.md` §7 — o footgun e por que ele é fechado no tipo.
- `CueMe/Model/MemoryNote.swift:24-27` — o `Equatable` por id.
- `CueMe/Model/Types.swift:58-100` — `TranscriptLine`.

## Superfície

```swift
enum TranscriptState: Codable, Sendable, Hashable {
    case notLoaded(turns: Int)
    case loaded([TranscriptLine])

    var lines: [TranscriptLine] { get }   // [] quando .notLoaded
    var turnCount: Int { get }            // conta correta nos dois casos
    var isLoaded: Bool { get }
}
```

`lines` devolvendo `[]` em `.notLoaded` mantém os leitores existentes compilando.
Quem **escreve** precisa checar `isLoaded` — é isso que T011 vai usar.

```swift
// CueMeTests/Support/AssertDeepEqual.swift
func assertDeepEqual(
    _ lhs: MemoryNote, _ rhs: MemoryNote,
    file: StaticString = #filePath, line: UInt = #line
)
```

Compara campo a campo e falha **nomeando o campo divergente**. No fim, verifica
`Mirror(reflecting: lhs).children.count` contra uma constante pinada no arquivo —
para que um campo novo no modelo quebre o helper em vez de passar despercebido.

## Critérios de aceite (EARS)

- **AC1** — QUANDO duas notas diferem em qualquer campo, O SISTEMA DEVE falhar o
  `assertDeepEqual` citando o nome do campo.
- **AC2** — QUANDO um campo é adicionado a `MemoryNote` sem atualizar o helper,
  O SISTEMA DEVE falhar o teste de contagem de `Mirror`.
- **AC3** — QUANDO duas notas diferem apenas em campos que não são `id`,
  O SISTEMA DEVE falhar o `assertDeepEqual` mesmo que `XCTAssertEqual` passe —
  o teste assere as duas coisas, para documentar a armadilha.
- **AC4** — QUANDO uma nota carrega `.notLoaded(turns: 214)`, O SISTEMA DEVE
  reportar `turnCount == 214` e `lines == []`.
- **AC5** — QUANDO `TranscriptState` é codificado e decodificado, O SISTEMA DEVE
  preservar o caso e a carga.

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testFailsNamingTheDivergentField` | `CueMeTests/AssertDeepEqualTests.swift` | AC1 |
| `testFailsWhenTheModelGainsAField` | idem | AC2 |
| `testEqualByIdIsNotDeepEqual` | idem | AC3 |
| `testNotLoadedReportsTurnCountWithoutLines` | `CueMeTests/TranscriptStateTests.swift` | AC4 |
| `testCodableRoundTripsBothCases` | idem | AC5 |

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] `MemoryNote.transcript` é `TranscriptState`; nenhum call site quebrado
- [ ] `assertDeepEqual` cobre **todos** os campos e tem a contagem de `Mirror` pinada
- [ ] AC3 demonstra explicitamente que `XCTAssertEqual` passaria
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

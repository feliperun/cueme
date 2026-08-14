---
id: T012
title: NoteDocumentReader e round-trip
depends_on: [T010, T011]
branch: felipe/okf-T012-note-reader
commit: "feat(okf): read note markdown as the durable source"
size: L
---

## Objetivo

O lado da leitura. Depois desta tarefa, todo campo que o writer emite é parseado de
volta — que é a premissa inteira da refatoração. É também onde as sete regras de
robustez viram teste: o que acontece quando o usuário edita o arquivo à mão.

## Escopo

### PODE TOCAR
- `CueMe/Model/OKF/NoteDocumentReader.swift` — novo
- `CueMe/Model/MemoryNote.swift` — adicionar `unknownFrontmatterYAML` e
  `residualMarkdown` se ainda não existirem
- `CueMeTests/NoteDocumentRoundTripTests.swift` — novo
- `CueMeTests/NoteDocumentExternalEditTests.swift` — novo
- `CueMeTests/Fixtures/` — fixtures adicionais

### NÃO PODE TOCAR
- `CueMe/Model/OKF/NoteDocumentWriter.swift` — se o writer estiver errado, é
  stop-and-report, não conserto silencioso aqui
- `CueMe/Model/CorpusStore.swift` — é T013

## Contexto obrigatório

- `specs/okf-corpus/design.md` §4 inteira (as gramáticas) e **§5 inteira** (as sete
  regras de robustez — cada uma é um AC).
- `specs/okf-corpus/constitution.md` §4, "A armadilha do `Equatable`".
- `CueMeTests/Support/AssertDeepEqual.swift` (T009) — use, não reescreva.

## Superfície

```swift
enum NoteDocumentReader {
    /// `nil` quando não há frontmatter ou `type` está vazio — o arquivo não é
    /// uma nota do CueMe e o loader deve ignorá-lo.
    static func read(_ markdown: String, slug: String, turns: Int) -> MemoryNote?
}
```

`turns` vem de `x_cueme_transcript.turns` no próprio documento; o parâmetro existe
para o chamador poder sobrescrever quando já carregou a transcrição. O estado
resultante é `.notLoaded(turns:)` — este reader **nunca** lê `raw/`.

## Critérios de aceite (EARS)

Os cinco de round-trip:

- **AC1** — QUANDO uma fixture é escrita, lida e escrita de novo, O SISTEMA DEVE
  produzir bytes idênticos à primeira escrita.
- **AC2** — QUANDO uma fixture é escrita e lida, O SISTEMA DEVE devolver uma nota
  `assertDeepEqual` à original.
- **AC3** — QUANDO `contracts/note.md` é lido, O SISTEMA DEVE reconstruir a fixture
  rica com todos os ids de domínio preservados.
- **AC4** — QUANDO o documento não tem frontmatter ou `type` está vazio, O SISTEMA
  DEVE devolver `nil`.
- **AC5** — QUANDO uma nota escrita à mão, sem nenhum marcador, é lida, O SISTEMA
  DEVE devolver corpo, título e labels, e coleções vazias no resto.

Os sete de edição externa (design §5):

- **AC6** — QUANDO o `# H1` difere do `title` do frontmatter, O SISTEMA DEVE fazer o
  H1 vencer e `titleSource` virar `.user`.
- **AC7** — QUANDO um item aparece sem `<!--cueme …-->`, O SISTEMA DEVE cunhar UUID
  novo e adotá-lo; a **segunda** escrita DEVE ser idempotente.
- **AC8** — QUANDO o usuário renomeia `## Pendências` para `## To-do`, O SISTEMA
  DEVE preservar os itens e regerar o título canônico.
- **AC9** — QUANDO uma linha de item está malformada dentro de uma seção conhecida,
  O SISTEMA DEVE mandá-la para `residualMarkdown` e nunca descartá-la.
- **AC10** — QUANDO há chave desconhecida no frontmatter, O SISTEMA DEVE preservá-la
  através de um ciclo completo de save.
- **AC11** — QUANDO o usuário acrescenta `## Apêndice` depois da última seção,
  O SISTEMA DEVE preservá-lo.
- **AC12** — QUANDO um `- [ ]` é marcado como `- [x]` no arquivo, O SISTEMA DEVE
  refletir `isDone` e **nada mais no arquivo DEVE mudar** no próximo save.

## Testes (TDD, red primeiro)

`NoteDocumentRoundTripTests` — AC1 a AC5. Fixtures obrigatórias: (a) a nota rica do
golden, (b) uma nota escrita à mão, (c) uma com unicode, emoji e RTL, (d) uma cujo
corpo contém `<!-- cueme:minutes -->` literal.

`NoteDocumentExternalEditTests` — AC6 a AC12, uma função por AC, cada uma terminando
com "salva e faz diff do arquivo inteiro contra o esperado".

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] Nenhum teste de round-trip usa `XCTAssertEqual` entre duas `MemoryNote`
- [ ] AC7 testa **as duas metades**: o id é cunhado, e a segunda escrita é estável
- [ ] Os 12 ACs com teste nomeado, cada um visto falhar antes
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

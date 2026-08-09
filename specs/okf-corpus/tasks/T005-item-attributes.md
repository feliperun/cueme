---
id: T005
title: NoteItemAttributes — codec do comentário inline
depends_on: [T003]
branch: felipe/okf-T005-item-attributes
commit: "feat(okf): add inline item attribute codec"
size: S
---

## Objetivo

Cada item durável dentro do corpo — pendência, decisão, questão, anotação, tópico,
card de coach, artefato, turno de transcrição — carrega um UUID estável e alguns
campos não-visíveis num flow mapping YAML dentro de um comentário HTML no fim da
linha de âncora. Este é o codec dessa linha. Sem ele, todo item vira item novo a
cada leitura e os ids do domínio se perdem.

## Escopo

### PODE TOCAR
- `CueMe/Model/OKF/NoteItemAttributes.swift` — novo
- `CueMeTests/NoteItemAttributesTests.swift` — novo

### NÃO PODE TOCAR
- Qualquer gramática de seção — é T010/T012
- `CueMe/Model/OKF/OKFFrontmatter.swift`

## Contexto obrigatório

- `specs/okf-corpus/design.md` §4.2 (o que fica visível e o que fica no comentário,
  e por quê) e a política de aspas em §3 — vale igual dentro do flow mapping.
- `specs/okf-corpus/contracts/note.md` — todas as formas reais de comentário.

## Superfície

```swift
struct NoteItemAttributes {
    subscript(key: String) -> OKFValue? { get }
    var uuid: (String) -> UUID? { get }
    var date: (String) -> Date? { get }
    var double: (String) -> Double? { get }
    var string: (String) -> String? { get }
    var strings: (String) -> [String]? { get }
    var isEmpty: Bool { get }
}

enum NoteItemAttributeCodec {
    /// Emite `<!--cueme {k: v, …}-->`; string vazia quando não há atributo.
    static func encode(_ pairs: [(String, OKFValue)]) -> String

    /// Separa o texto visível do comentário. Sempre devolve texto;
    /// atributos vazios quando não há comentário ou ele está malformado.
    static func decode(_ line: String) -> (text: String, attributes: NoteItemAttributes)
}
```

## Regras

- Formato exato emitido: um espaço antes de `<!--cueme `, um espaço depois de
  `cueme`, sem espaço antes de `-->`. A ordem dos pares é a ordem do array.
- O comentário é reconhecido apenas **no fim da linha**: `\s*<!--cueme (\{.*\})-->\s*$`.
  Use o **último** casamento da linha, para que um `-->` dentro do texto visível não
  trunque nada.
- Comentário malformado (YAML que não parseia, chaves desbalanceadas) → a linha
  inteira é texto, atributos vazios. Nunca crashe, nunca descarte.
- Datas entram e saem como string entre aspas duplas, como no frontmatter.

## Critérios de aceite (EARS)

- **AC1** — QUANDO a linha não tem comentário, O SISTEMA DEVE devolver o texto
  inteiro e atributos vazios.
- **AC2** — QUANDO o texto visível contém `-->`, O SISTEMA DEVE não truncar o texto
  e ainda encontrar o comentário no fim.
- **AC3** — QUANDO o comentário está malformado, O SISTEMA DEVE tratar a linha
  como texto puro e não lançar.
- **AC4** — QUANDO um atributo pedido não existe, O SISTEMA DEVE devolver `nil` sem
  erro.
- **AC5** — QUANDO um conjunto de pares é codificado e decodificado, O SISTEMA DEVE
  devolver os mesmos valores tipados, incluindo lista de strings e data.
- **AC6** — QUANDO cada linha âncora do golden `contracts/note.md` é decodificada,
  O SISTEMA DEVE extrair o `id` de todas.

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testLineWithoutCommentKeepsFullText` | `NoteItemAttributesTests` | AC1 |
| `testArrowInVisibleTextDoesNotTruncate` | idem | AC2 |
| `testMalformedCommentDegradesToPlainText` | idem | AC3 |
| `testMissingAttributeIsNil` | idem | AC4 |
| `testRoundTripsTypedValues` | idem | AC5 |
| `testDecodesEveryAnchorInTheGoldenNote` | idem | AC6 |

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] Os 6 ACs com teste nomeado, cada um visto falhar antes
- [ ] Nenhum `try!` nem `fatalError` no caminho de decode
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

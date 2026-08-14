---
id: T006
title: OKFBundle — layout, slugs e nomes reservados
depends_on: [T002]
branch: felipe/okf-T006-bundle-layout
commit: "feat(okf): add corpus layout and slug rules"
size: M
---

## Objetivo

O vocabulário de caminhos do corpus num lugar só: onde fica o `.md` de uma nota,
onde fica a pasta irmã, onde fica `raw/`, quais nomes são reservados, e como um
título vira um slug único dentro do seu diretório. Todo o resto do plano depende
dessas regras; hoje elas estão espalhadas entre `SessionArchive.folderName` e
`ProjectWorkspaceStore.slug`.

Nada de I/O nesta tarefa — só cálculo de nome e caminho, para ser testável sem
tocar o filesystem.

## Escopo

### PODE TOCAR
- `CueMe/Model/OKF/OKFBundle.swift` — novo
- `CueMeTests/OKFBundleTests.swift` — novo

### NÃO PODE TOCAR
- `CueMe/Model/SessionArchive.swift` e `ProjectWorkspaceStore.swift` — continuam
  como estão; a substituição é T013/T016. Copie a lógica de slug, não a mova ainda.

## Contexto obrigatório

- `specs/okf-corpus/design.md` §1 — layout, nomes reservados, regras de slug.
- `CueMe/Model/ProjectWorkspaceStore.swift:56-62` — o `slug` atual, que é a base.
- `CueMe/Model/SessionArchive.swift:4-10` — `folderName`, para o nome de sessão sem
  título.

## Superfície

```swift
enum OKFBundle {
    static let okfVersion = "0.2"
    static let rawDirectoryName = "raw"
    static let attachmentsDirectoryName = "attachments"
    static let indexFileName = "index.md"
    static let logFileName = "log.md"
    static let agentsFileName = "AGENTS.md"

    /// Reservado em qualquer diretório.
    static func isReserved(_ name: String, atRoot: Bool) -> Bool

    static func slug(_ title: String) -> String
    static func uniqueSlug(_ title: String, taken: Set<String>) -> String
    static func untitledSlug(startedAt: Date) -> String   // "2026-08-08-1430", hora local

    static func noteURL(slug: String, in directory: URL) -> URL          // <dir>/<slug>.md
    static func noteFolder(slug: String, in directory: URL) -> URL       // <dir>/<slug>/
    static func rawDirectory(slug: String, in directory: URL) -> URL     // <dir>/<slug>/raw/
    static func attachmentsDirectory(slug: String, in directory: URL) -> URL
}
```

## Regras

- **Slug**: dobra diacrítico, runs de não-alfanumérico viram `-`, minúsculo, sem
  `-` nas bordas, no máximo 54 caracteres. Título que reduz a vazio vira `nota`.
- **Unicidade é por diretório.** Colisão recebe `-2`, `-3`, … O `taken` recebido já
  contém os slugs irmãos.
- **Reservados**: `index`, `log` em qualquer nível; `raw` dentro de pasta de nota;
  `AGENTS` só na raiz. Um slug que bata com reservado é rejeitado e cai no próximo
  candidato livre (`index` → `index-2`).
- **Sessão sem título**: `yyyy-MM-dd-HHmm` em `en_US_POSIX`, timezone local — o nome
  precisa fazer sentido para quem abre o Finder.

## Critérios de aceite (EARS)

- **AC1** — QUANDO duas notas irmãs geram o mesmo slug, O SISTEMA DEVE desambiguar
  com `-2`, depois `-3`.
- **AC2** — QUANDO o título gera um slug reservado (`raw`, `index`, `log`),
  O SISTEMA DEVE recusá-lo e usar o próximo livre.
- **AC3** — QUANDO uma sessão é criada sem título, O SISTEMA DEVE nomeá-la
  `yyyy-MM-dd-HHmm` em hora local.
- **AC4** — QUANDO o título tem acento, emoji, pontuação e espaços múltiplos,
  O SISTEMA DEVE produzir um slug só com `[a-z0-9-]`.
- **AC5** — QUANDO o título passa de 54 caracteres úteis, O SISTEMA DEVE truncar sem
  deixar `-` na borda.
- **AC6** — QUANDO o mesmo slug existe em dois diretórios diferentes, O SISTEMA DEVE
  aceitar os dois — a unicidade é por diretório.

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testDisambiguatesSiblingSlugs` | `OKFBundleTests` | AC1 |
| `testRejectsReservedSlugs` | idem | AC2 |
| `testUntitledSessionUsesLocalTimestamp` | idem | AC3 |
| `testFoldsDiacriticsAndPunctuation` | idem | AC4 |
| `testTruncatesWithoutTrailingHyphen` | idem | AC5 |
| `testSlugUniquenessIsPerDirectory` | idem | AC6 |

AC3 exige data injetada e um `TimeZone` fixo no teste — nada de `Date()` solto.

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] Os 6 ACs com teste nomeado, cada um visto falhar antes
- [ ] Zero I/O de filesystem no arquivo e nos testes
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

---
id: T002
title: Adicionar Yams via SPM
depends_on: [T001]
branch: felipe/okf-T002-add-yams
commit: "chore(deps): add Yams for YAML frontmatter"
size: S
---

## Objetivo

O app passa a poder ler e escrever YAML de verdade. Hoje o frontmatter é parseado
com um `split` na primeira `:` de cada linha (`NoteDocument.swift:72-77`), que não
sabe aninhar, não sabe lista de mapping e quebra com `:` dentro do valor. O
frontmatter OKF exige as três coisas. Como o `.md` vai virar a **única** cópia
durável da nota, um parser incompleto deixa de ser degradação e vira perda de
dados.

Nada é ligado nesta tarefa: só a dependência, um smoke test e o ADR.

## Escopo

### PODE TOCAR
- `CueMe.xcodeproj/project.pbxproj` — referência SPM e vínculo com o target
- `CueMeTests/YamsSmokeTests.swift` — novo
- `docs/adr/0044-yaml-frontmatter-via-yams.md` — novo
- `docs/adr/README.md` — linha do 0044

### NÃO PODE TOCAR
- Qualquer coisa em `CueMe/Model/` — o codec é T003
- `.sentrux/rules.toml` — nunca, em nenhuma tarefa

## Contexto obrigatório

- `CueMe.xcodeproj/project.pbxproj` — procure por `XCRemoteSwiftPackageReference "Sparkle"`
  e replique a estrutura (`XCRemoteSwiftPackageReference`, `XCSwiftPackageProductDependency`,
  entrada em `packageProductDependencies` do target `CueMe`).
- `scripts/package.sh` — o fluxo de build assinado que precisa continuar funcionando.
- `docs/adr/0003-sentrux-structural-quality-gates.md` — formato de ADR usado no repo.

## Decisões já tomadas

- Pacote: `https://github.com/jpsim/Yams`, **versão pinada** (`exact` ou
  `upToNextMinor`), não `branch`.
- Yams fica confinado a `CueMe/Model/OKF/`. Nenhum outro diretório importa Yams.
  Isso vai no ADR como regra, e T003 é quem passa a usá-lo.
- `Yams.Node` e `Yams.Emitter` **não são `Sendable`**. O ADR registra que eles só
  podem aparecer em chamadas síncronas não-escapantes e nunca podem ser guardados
  num tipo de modelo.

## Critérios de aceite (EARS)

- **AC1** — QUANDO o target de teste compila, O SISTEMA DEVE resolver `import Yams`.
- **AC2** — QUANDO um mapping YAML aninhado com lista de mappings é decodificado
  e reemitido, O SISTEMA DEVE devolver a mesma estrutura.
- **AC3** — QUANDO `./scripts/package.sh` roda, O SISTEMA DEVE produzir um `.dmg`
  assinado. Yams é libyaml (C); validar aqui e não no release.
- **AC4** — QUANDO `grep -rl "import Yams" CueMe/` roda, O SISTEMA DEVE não
  retornar nada fora de `CueMe/Model/OKF/` (vazio nesta tarefa).

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testYamsDecodesNestedMappingsAndSequences` | `CueMeTests/YamsSmokeTests.swift` | AC1, AC2 |

O red aqui é o build falhando por `no such module 'Yams'` antes de adicionar a
dependência. Registre isso no relatório.

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
./scripts/package.sh
```

Se `package.sh` falhar por falta de credencial de assinatura na máquina, **pare e
reporte** — não conclua a tarefa assumindo que passaria.

## Definition of done

- [ ] Dependência com versão pinada no `.pbxproj`, vinculada ao target `CueMe`
- [ ] Smoke test escrito, visto falhar, e passando
- [ ] ADR 0044 escrito e indexado no `docs/adr/README.md`
- [ ] `.dmg` assinado gerado com sucesso (ou falha reportada)
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

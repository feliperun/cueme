---
id: T007
title: Tirar diagnostics do modelo durável
depends_on: [T001]
branch: felipe/okf-T007-diagnostics-out
commit: "refactor(model): move session diagnostics out of the durable note"
size: M
---

## Objetivo

`SessionDiagnostics` guarda até 500 eventos de telemetria de runtime dentro do
arquivo do usuário. Isso é dado de desenvolvimento, não memória pessoal: latência
de STT, reconexões, durações. Sai do `MemoryNote` e vai para um log rotativo fora
do corpus. Fica persistido apenas o que o painel de Integridade realmente mostra.

## Escopo

### PODE TOCAR
- `CueMe/Model/MemoryNote.swift` — troca `diagnostics` por `integrity`
- `CueMe/Model/SessionDiagnostics.swift` — passa a hospedar também `NoteIntegrity`
- `CueMe/Model/DiagnosticsLog.swift` — novo
- `CueMe/Model/SessionPerformanceReport.swift` — `SessionIntegrityReport` lê `integrity`
- `CueMe/Model/AppModel.swift`, `AppModel+SessionMemory.swift`,
  `AppModel+AudioImport.swift`, `AppModel+LiveIntelligence.swift`,
  `CueMe/Model/SessionCoordinator.swift` — pontos de gravação de evento
- `CueMe/Views/HistorySessionDiagnostics.swift` — **deletar**
- `CueMe/Views/HistorySessionDetailView.swift` — remover o call site
- `CueMe/Views/SessionReviewPane.swift` — remove o bloco de performance, mantém integridade
- `CueMe/Model/UITestFixtures.swift` — fixture
- `CueMeTests/SessionRuntimeTests.swift`, `ReliabilityPolicyTests.swift`
- `docs/adr/0045-session-diagnostics-are-dev-telemetry.md` — novo
- `docs/adr/README.md`

### NÃO PODE TOCAR
- Qualquer coisa em `CueMe/Model/OKF/`

## Contexto obrigatório

- `specs/okf-corpus/design.md` §6 — campos deletados e adicionados.
- `CueMe/Model/SessionPerformanceReport.swift` — quais agregados a UI consome hoje.
- `CueMe/Views/SessionReviewPane.swift:100-120` — os dois blocos, para separar o que
  fica do que sai.

## Decisões já tomadas

```swift
struct NoteIntegrity: Codable, Sendable, Hashable {
    var recoveries: Int = 0
    var errors: Int = 0
}
```

`DiagnosticsLog`: ring de 500 em memória para a sessão corrente + append JSONL em
`~/Library/Logs/CueMe/diagnostics-yyyy-MM-dd.jsonl`, com rotação descartando
arquivos com mais de 7 dias. **Fora do corpus** — nunca sob `CorpusStore.rootURL`.

Consequência aceita e registrada no ADR: a UI de diagnóstico por nota desaparece e
a latência histórica das notas existentes não é recuperável.

## Critérios de aceite (EARS)

- **AC1** — QUANDO uma nota é salva, O SISTEMA DEVE persistir apenas `recoveries` e
  `errors`, e nenhum evento individual.
- **AC2** — QUANDO um evento de diagnóstico é registrado, O SISTEMA DEVE gravá-lo
  fora de `CorpusStore.rootURL`.
- **AC3** — QUANDO o painel de Integridade abre, O SISTEMA DEVE mostrar cobertura de
  áudio, falas transcritas, recuperações e erros.
- **AC4** — QUANDO um evento de `kind == .recovery` ou `.error` é registrado durante
  a sessão, O SISTEMA DEVE incrementar o contador correspondente em `integrity`.
- **AC5** — QUANDO existem arquivos de log com mais de 7 dias, O SISTEMA DEVE
  removê-los na próxima rotação.
- **AC6** — QUANDO `grep -rn "SessionDiagnostics" CueMe/` roda, O SISTEMA DEVE
  retornar apenas `DiagnosticsLog` e seu próprio arquivo de definição.

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testSavedNoteKeepsOnlyIntegrityCounters` | `CueMeTests/NoteIntegrityTests.swift` | AC1 |
| `testDiagnosticsLogWritesOutsideTheCorpus` | `CueMeTests/DiagnosticsLogTests.swift` | AC2 |
| `testIntegrityReportShowsFourAggregates` | `CueMeTests/ReliabilityPolicyTests.swift` | AC3 |
| `testRecoveryAndErrorEventsIncrementIntegrity` | idem | AC4 |
| `testRotationDropsLogsOlderThanSevenDays` | `DiagnosticsLogTests` | AC5 |

AC5 exige data injetada. Nada de `Thread.sleep` nem data de sistema.

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] `MemoryNote.diagnostics` não existe mais
- [ ] `HistorySessionDiagnostics.swift` deletado e sem call sites órfãos
- [ ] ADR 0045 escrito e indexado, incluindo a perda aceita
- [ ] Os ACs com teste nomeado, cada um visto falhar antes
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

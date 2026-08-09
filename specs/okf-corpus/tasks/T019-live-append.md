---
id: T019
title: Append incremental de transcrição e guard de mtime
depends_on: [T016]
branch: felipe/okf-T019-live-append
commit: "perf(okf): append transcript turns during live sessions"
size: M
---

## Objetivo

Durante uma sessão ao vivo, `LiveSnapshotWriter` é chamado de oito lugares. Com o
Markdown como única cópia durável, cada chamada renderizaria o documento inteiro —
numa reunião de uma hora, centenas de turnos re-renderizados a cada poucos segundos,
com STT e coach rodando ao lado.

Separar a transcrição já resolveu a maior parte: o `.md` da nota é pequeno agora.
Falta fechar os dois pontos restantes — anexar turno em vez de re-renderizar
`raw/transcript.md`, e não recarregar o corpus inteiro quando nada mudou no disco.

## Escopo

### PODE TOCAR
- `CueMe/Model/LiveSnapshotWriter.swift` — reescrita
- `CueMe/Model/CorpusStore.swift` — `appendTranscript`, `corpusChanged(since:)`
- `CueMe/Model/AppModel+MemoryNotes.swift` — `reloadWorkspaceFromDisk`
- `CueMeTests/LiveSnapshotWriterTests.swift`
- `CueMeTests/CorpusReloadTests.swift` — novo

### NÃO PODE TOCAR
- `CueMe/Model/OKF/TranscriptDocument.swift` — `renderTurns` já existe desde T011
- `CueMe/Model/SessionCoordinator.swift` — só se um call site quebrar; nesse caso,
  reporte antes

## Contexto obrigatório

- `CueMe/Model/LiveSnapshotWriter.swift` — a coalescência atual e os oito call sites
  (`SessionCoordinator`, `AppModel+SessionMemory`, `AppModel`).
- `CueMe/Model/AppModel+MemoryNotes.swift:17-30` — `reloadWorkspaceFromDisk` dispara
  em toda ativação do app. Leia o comentário do guard de `CUEME_UI_TESTING`: ele
  descreve uma race real. **Não** mexa nesse guard aqui; T021 é quem trata dele.
- `specs/okf-corpus/design.md` §4.11 — a garantia de que append e render completo
  produzem os mesmos bytes.

## Decisões já tomadas

- `appendTranscript` anexa **só** os blocos dos turnos finais novos, usando
  `TranscriptDocument.renderTurns`. Não reimplemente a gramática.
- O resultado de N appends tem que ser **byte-idêntico** a um render completo dos
  mesmos N turnos. Essa é a invariante que permite o append existir.
- `corpusChanged(since:)` compara mtime dos `.md` da árvore. Quando nada mudou,
  `reloadWorkspaceFromDisk` sai sem ler nada.
- O `.md` da nota continua sendo re-renderizado por inteiro no snapshot — ele é
  pequeno agora. Não invente escrita parcial dele.

## Critérios de aceite (EARS)

- **AC1** — QUANDO um turno é finalizado numa sessão ao vivo, O SISTEMA DEVE anexar
  só o bloco dele, sem reescrever o arquivo.
- **AC2** — QUANDO nenhum `.md` mudou de mtime, O SISTEMA DEVE pular `loadNotes()`
  inteiro.
- **AC3** — QUANDO a sessão termina, o arquivo produzido por appends sucessivos DEVE
  ser byte-idêntico a um render completo dos mesmos turnos.
- **AC4** — QUANDO um `.md` muda no disco por fora, O SISTEMA DEVE detectar e
  recarregar.
- **AC5** — QUANDO a transcrição de uma nota está `.notLoaded`, O SISTEMA DEVE ainda
  conseguir anexar turnos novos sem carregar os antigos.
- **AC6** — QUANDO dois appends acontecem em sequência, O SISTEMA DEVE não duplicar
  turno nem perder nenhum.

## Testes (TDD, red primeiro)

| Teste | Arquivo | Prova |
|---|---|---|
| `testAppendWritesOnlyTheNewTurn` | `LiveSnapshotWriterTests` | AC1 |
| `testUnchangedCorpusSkipsReload` | `CorpusReloadTests` | AC2 |
| `testAppendedFileMatchesFullRender` | `LiveSnapshotWriterTests` | AC3 |
| `testExternalChangeTriggersReload` | `CorpusReloadTests` | AC4 |
| `testAppendWorksWithUnloadedTranscript` | `LiveSnapshotWriterTests` | AC5 |
| `testConsecutiveAppendsDoNotDuplicate` | idem | AC6 |

AC1 conta escritas com um espião, ou compara tamanho antes/depois — **nunca** mede
tempo. AC4 seta mtime explicitamente; nada de `Thread.sleep` esperando o relógio.

## Verificação

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
sentrux check . && sentrux gate .
```

## Definition of done

- [ ] Append reaproveita `renderTurns`; nenhuma gramática duplicada
- [ ] AC3 provado por bytes
- [ ] Guard de `CUEME_UI_TESTING` intocado
- [ ] Os 6 ACs com teste nomeado, cada um visto falhar antes
- [ ] Build, unit, `sentrux check`, `sentrux gate` verdes

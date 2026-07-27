# Fechar as diferenças do redesign "reunião como nota estruturada"

> **Repositório:** [`feliperun/cueme`](https://github.com/feliperun/cueme)
> **Issue:** [#37](https://github.com/feliperun/cueme/issues/37)
> **Linear:** não aplicável — repositório pessoal, sem credencial/configuração Linear
> **PR atual:** pendente
> **Branch atual:** `felipe/gh-37-shell-chrome`
> **Build:** `xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
> **Test:** `xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' test`
> **Unit/Integration:** `xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test`
> **UI E2E:** `xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -only-testing:CueMeUITests test`
> **Lint/Gate:** `sentrux check . && sentrux gate .`
> **CI:** [`.github/workflows/quality.yml`](../../.github/workflows/quality.yml)
> **Modo:** automático, com checkpoint de merge entre PRs dependentes

### Estado de execução

| ID | Issue | Task | Depends on | Status |
|---|---|---|---|---|
| p1a | #37 | Preservar comandos e contratos E2E do shell | — | **pending** |
| p1b | #37 | Implementar titlebar e migrar capacidades do HeaderBar | p1a | **pending** |
| p1c | #37 | Implementar árvore hierárquica e live sintético | p1b | **pending** |
| p1d | #37 | Corrigir filtros, contagens e identifiers da note list | p1c | **pending** |
| p1e | #37 | Verificar, documentar e abrir PR 1 | p1d | **pending** |
| p2 | #37 | Header, masthead e blank note focável | PR 1 merged | **pending** |
| p3 | #37 | Contrato seguro e lossless dos meeting blocks | PR 2 merged | **pending** |
| p4 | #37 | Documento único de reunião com paridade do review | PR 3 merged | **pending** |
| p5 | #37 | Coach herói e live layout | PR 4 merged | **pending** |
| p6 | #37 | Copy, token cleanup, pixel polish e docs finais | PR 5 merged | **pending** |

### Commits

| Hash | Mensagem |
|---|---|

## Context

O redesign do commit `a785259` (`feat(ui): note-first three-column workspace redesign`)
landou a estrutura inicial: tokens e fontes, shell de três colunas, `LiveNoteView`,
`LiveMemoryDrawer`, `AskCueMeBar`, `SessionHealthDisclosure` e `CoachCuesBlock`.
Ainda faltam as superfícies do protótipo (`temp/CueMe v2.dc.html`, frames em
`temp/showcase/`): chrome sem a faixa antiga, masthead documental, blocos de reunião,
review com hierarquia de leitura, coach herói e blank note coerente.

Decisões de produto já tomadas:

- Copy em inglês nas superfícies do redesign.
- Review com aparência de documento e edição inline, sem perder nenhuma capacidade atual.
- Meeting blocks entram nesta rodada e têm representação lossless em `note.md`.

Este plano foi revisado contra o codebase real. A implementação deve seguir uma única
arquitetura documental e manter o app compilando e com testes verdes ao final de cada PR.

---

## Decisões de arquitetura e invariantes

### Um único renderer para `Document`

- `MemoryNoteEditor` + `MarkdownBlockEditor` são o compositor canônico do tab `Document`
  para notas escritas, importadas e gravadas.
- `SessionReviewPane` não ganha um segundo `ReviewDocument`. Ele permanece temporariamente
  como tab secundário de compatibilidade até os blocos alcançarem paridade; não é a
  superfície primária.
- Os tabs Transcript, Minutes, Coach, Notes, Takeaways e Generated continuam como projeções
  secundárias durante a migração. Removê-los é follow-up, não requisito deste redesign.
- Meeting blocks são projeções embutidas de dados do `session.json`; a âncora em `note.md`
  controla presença e ordem, sem duplicar transcript/minutes/coach no Markdown.

### Autoridade do corpus

- `note.md` permanece autoritativo para título, metadata e corpo escrito.
- `session.json` permanece o sidecar estruturado para transcript, coach, minutes, evidence e
  diagnósticos.
- Remover uma âncora externamente remove o bloco. O app nunca a recria durante load/reindex.
- SQLite/FTS5/sqlite-vec continuam derivados. Nenhuma etapa escreve conhecimento apenas no
  banco.

### Compatibilidade de interação

- Accessibility identifiers são contratos, conforme ADR 0029.
- Antes de remover um controle, seu comportamento, shortcut, identifier e accessibility
  value devem existir no novo host ou o E2E deve mudar no mesmo PR.
- O editor do primeiro bloco permanece montado e focável mesmo com a nota vazia.
- Attach, Reveal in Finder, source mode, formatação, evidence, add/delete, follow-up e
  mensagens de erro não podem sumir durante o restyle.

### TDD e PRs verdes

- Cada mudança comportamental começa por teste falhando no mesmo PR.
- Testes não ficam acumulados numa fase final.
- Cada PR roda build, unit/integration, UI E2E e Sentrux antes de ser considerado pronto.
- ADRs e docs estruturais acompanham o código que implementa a decisão.

---

## Fora de escopo

- **Pause de captura.** `SessionState.paused` existe, mas não há caminho de pause/resume no
  stack de áudio. O transporte não mostra uma ação sem backing.
- **Live virar `SessionRecord` no `history` durante captura.** O live continua como linha
  sintética ligada a `activeProjectID`; a persistência final ocorre no stop.
- **`used at mm:ss`.** `CoachFeedback` não guarda timestamp de uso. Mostrar `✓ used` e
  `cue at mm:ss`, derivado de `CoachCard.ts`; não inventar telemetria.
- **Terceiro participante inferido.** O modelo tem apenas `.self` e `.other`. Avatares usam
  participantes reais e deduplicam `KnowledgePerson`; não fabricam três pessoas.
- **`Mark this moment`.** Não há bookmark/marker no modelo. O item fica fora; adicionar esse
  comportamento exige feature e teste próprios.
- **Waveform histórico rolante no live.** Níveis atuais podem alimentar um meter; não há
  buffer histórico pronto para desenhar waveform real.

---

## Ordem e dependências

| PR | Resultado | Depende de |
|---|---|---|
| 1 | Shell chrome sem `HeaderBar`, preservando todos os comandos | baseline |
| 2 | Header, masthead e blank note com contratos preservados | PR 1 |
| 3 | Contrato lossless e seguro dos meeting blocks | PR 2 |
| 4 | Documento único de reunião com paridade do review | PR 3 |
| 5 | Coach herói e live layout com ações reais | PR 4 |
| 6 | Copy, token cleanup, pixel polish e docs finais | PRs 1–5 |

Não misturar PRs. Se uma dependência impedir um PR de compilar sozinho, manter o renderer ou
controle legado até o PR seguinte em vez de criar um estado intermediário quebrado.

---

## Fase 0 — Baseline

Antes de tocar arquivos existentes:

```bash
sentrux gate --save .
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -only-testing:CueMeUITests test
```

- Registrar o diff inicial e preservar mudanças do usuário.
- Conferir `git diff -- .sentrux/baseline.json` após `gate --save`.
- Não commitar baseline regravada para mascarar regressão. Atualizá-la somente quando o
  resultado estrutural melhorar de forma intencional e documentada.

---

## PR 1 — Shell chrome e migração do `HeaderBar`

### 1.1 TDD: preservar comandos e E2E

Antes de remover `HeaderBar`, atualizar/adicionar cenários que provem:

- `session.primary` inicia e para, mantém `⌘↵` e expõe label coerente com o estado.
- Modo passivo tem `Stop & save`.
- `capture.microphone` e `capture.system` mantêm accessibility values
  (`waiting|active|silent|recovering|unavailable`).
- Theme permanece alcançável e expõe o valor atual.
- Nova sessão/`⌘N`, configuração, participant naming e import retry continuam acessíveis.
- O pós-stop usa um novo anchor estável `workspace.library`, substituindo asserts no texto
  `"Biblioteca"`.

Atualizar `CueMeUITests/CueMeMemoryE2ETests.swift` no mesmo PR. Não esperar o PR 6.

### 1.2 Mapa obrigatório de capacidades

| Capacidade atual | Novo host | Contrato |
|---|---|---|
| Start/stop | botão persistente no footer da árvore | `session.primary`, `⌘↵` |
| Stop no live completo | transporte escuro | `live.stop` |
| Stop no modo passivo | `LiveTransportBar` | ação `app.stop()` |
| Mic/system health + repair | `LiveHealthStrip` também em `.preparing` | `capture.microphone`, `capture.system`, values |
| Theme | menu próprio no workspace header/titlebar, não submenu aninhado | `theme.preference`, value |
| Pin, training, profiles, Camera Rail, setup, settings, update | menu `CueMe ⌄` | ações atuais |
| Nova sessão | menu `CueMe ⌄` | `app.newSession()`, `⌘N` |
| Nomear participantes live | masthead/brief bar do live | `setParticipantName(_:for:)` |
| Silence coach | overflow do transporte live | `toggleSilence()` |
| Import progress/retry/dismiss | overlay reancorado no footer/titlebar | `ImportStatusRow` |
| Estado library pós-stop | note column/masthead | `workspace.library` |

Só depois desta tabela estar implementada remover `HeaderBar`,
`ChannelHealthButton` e helpers realmente órfãos de `ControlsBar.swift`.

### 1.3 `RootWorkspaceShell` e titlebar

- Adicionar faixa de 40pt no topo do shell, `Theme.tree`, hairline `Theme.line` e região
  arrastável que não bloqueia controles.
- Reservar espaço à esquerda para os semáforos do macOS e validar em janela normal/zoom.
- À direita, quando live: ponto âmbar 7pt pulsante + `Recording · mm:ss`, sem pill.
- Manter `CaptureHealthAlert` visível nos estados atuais e seu identifier.

### 1.4 `ProjectTreeColumn`

- `workspaceHeader` vira menu real, respeitando o mapa acima.
- Adicionar disclosure e filhos de projeto a partir de:

  ```swift
  app.history
      .filter { $0.projectID == project.id }
      .sorted { $0.startedAt > $1.startedAt }
  ```

  Não usar `app.libraryNotes`, já filtrado por projeto, tab e busca.
- Child rows usam `tree.note.<uuid>`, nunca `session.<uuid>`, que pertence à coluna 2.
- Projeto selecionado e projeto da nota selecionada são tratados como expandidos.
- Clicar no filho seleciona projeto e nota, mantendo a coluna 2 consistente.
- Durante captura, renderizar filho live sintético sob `activeProjectID`, com ponto âmbar e
  ação `app.showLiveSession()`. Não procurar record live em `history`.
- Preservar `ImportStatusRow` mesmo removendo o botão visual de import do footer.

### 1.5 `NoteListColumn`

- Mostrar `All N`, `Meetings`, `Notes` como no protótipo.
- Calcular `N` antes de `historyTypeFilter`; não usar `app.libraryNotes.count`.
- Alinhar o predicado Meetings ao mesmo conceito do tag visível:
  `containsRecording || origin == .live` e kinds de meeting/audio.
- Cobrir contagem e predicado com teste unitário.

### 1.6 Verificação do PR 1

- E2E de start/stop, degraded capture, theme, note selection e import passam.
- Nenhuma query `session.<uuid>` resolve mais de um elemento.
- Modo passivo e estado pós-stop não têm dead ends.
- `sentrux check . && sentrux gate .`.

---

## PR 2 — Header, masthead e blank note

### 2.1 TDD: contratos de edição/navegação

Escrever/ajustar testes antes do restyle:

- Tabs secundários continuam acionáveis como `Button` com `session.tab.*`.
- Rename continua um `Button` `note.rename`, abrindo `note.title.input` e
  `note.title.save`.
- Labels, projeto, participantes e Reveal in Finder continuam alcançáveis.
- `note.editor.source`, `note.editor.raw`, Attach e format shortcuts continuam funcionais.
- Nota recém-criada sempre expõe `note.block.editor.0` e aceita o primeiro keystroke.
- Masthead existe em nota escrita, reunião/import, review compatível e blank note.

### 2.2 `NoteMasthead`

Criar `CueMe/Views/NoteMasthead.swift` e montá-lo na mesma fase em:

- `MemoryNoteEditor`;
- `SessionReviewPane` enquanto ainda existe como tab secundário;
- blank note.

Comportamento:

- Eyebrow com data/kind/duração usando dados reais.
- Título `.read(41, .semibold)`, mas manter nesta rodada o Button+popover de rename para
  preservar accessibility e evitar mudança simultânea de contrato.
- Avatares somente de `.self` e `.other`, com `KnowledgePerson` deduplicado; written notes
  sem participantes não ganham placeholders falsos.
- Labels, project e participants popovers migram para o masthead mantendo identifiers.
- Reveal in Finder permanece como ação explícita no masthead/overflow.

### 2.3 Header de uma linha

- Breadcrumb do projeto.
- Segmented `Document | Transcript | Minutes`.
- Tabs secundários permanecem Buttons visíveis numa linha compacta durante a migração.
  Não colocá-los em `Menu` fingindo preservar o tipo XCUI.
- Source mode é controlado por estado levantado de `MemoryNoteEditor`; manter
  `note.editor.source`.
- Attach, attachment count e Reveal permanecem no header/overflow.
- Share e Export entram apenas quando têm ação real.
- Follow-up editável não migra para um menu de geração.

### 2.4 Documento e box model

- Faixa externa de 720pt incluindo padding de 44pt em cada lado; em SwiftUI, aplicar padding
  dentro da largura final, não produzir 720 + 88pt.
- Corpo efetivo de leitura: aproximadamente 632pt.
- Background `Theme.paper`; top 30, bottom 26.
- Masthead participa do mesmo `ScrollView`, acima dos blocos.
- `WaveformPlayerView` só sai da faixa fixa depois que `RecordingBlock` existir no PR 4.

### 2.5 Blank note sem regressão de foco

- Manter `MarkdownBlockEditor` montado e no topo em todo momento.
- Masthead `Untitled` fica acima do primeiro bloco; cards ficam abaixo.
- Cards somem quando `document.markdown` deixa de ser vazio; o editor nunca depende disso.
- Adicionar `/ Insert block` além de Record/Import.
- Preservar `home.new-note` → primeiro editor focável.

### 2.6 Verificação do PR 2

- Rodar os E2E de rename, source mode, visual block editor, labels, project e tabs.
- Validar foco sem sleeps.
- Comparar note e blank com os frames light/dark.
- Atualizar `docs/ARCHITECTURE.md` se o estado do header/editor mudar estruturalmente.

---

## PR 3 — Contrato seguro dos meeting blocks

### 3.1 ADR e gramática

Criar ADR no mesmo commit do parser, relacionando ADR 0031 e ADR 0034.

O ADR compara:

- HTML comment invisível;
- fenced block `cueme:*`;
- link/reference syntax.

Decisão deste plano: HTML comment com namespace separado dos delimitadores do body:

```markdown
<!-- cueme:block:recording -->
<!-- cueme:block:coach-cues -->
<!-- cueme:block:transcript -->
<!-- cueme:block:minutes -->
<!-- cueme:block:action-items -->
```

Gramática ancorada:

```text
^\s*<!--\s*cueme:block:(recording|coach-cues|transcript|minutes|action-items)\s*-->\s*$
```

- `cueme:body:start` e `cueme:body:end` continuam reservados exclusivamente a
  `NoteDocument`.
- Unknown anchors permanecem texto/parágrafo lossless.
- Slugs usam hífen, nunca `_`.

### 3.2 Modelo e semântica de edição

Adicionar `MarkdownBlockKind` para os cinco blocos e uma propriedade
`isEmbeddedProjection`.

Aplicar a propriedade em todos os caminhos, não apenas `blockSurface`:

- parse/serialize;
- `transform`;
- split/Return;
- Backspace/merge;
- duplicate;
- drag/reorder;
- slash transform/insert;
- focus placement;
- placeholder/font/minimum height.

Regras:

- Embedded block não usa `MarkdownBlockTextView`.
- Comando aplicado sobre bloco de texto não vazio insere a projeção depois dele; nunca limpa
  conteúdo silenciosamente.
- Return/insert cria parágrafo vazio depois e foca esse parágrafo.
- Backspace no início do bloco seguinte remove a projeção como o divider, sem absorver texto.
- Cada kind é singleton por documento; duplicate fica desabilitado.
- Remover/reordenar a âncora é permitido e persiste em `note.md`.

### 3.3 Seeding e migração respeitando autoridade humana

Adicionar metadata canônica em frontmatter, por exemplo:

```yaml
meeting-block-layout-version: 1
```

- Nova sessão concluída recebe a stack default e a versão uma única vez.
- Nota legada com sidecar de reunião, versão ausente e nenhuma âncora recebe migração única.
- Depois da versão gravada, load/reindex nunca repõe âncora removida externamente.
- O campo precisa round-trip em `NoteDocument`/metadata e teste filesystem.
- Nenhum healing automático por ausência de anchor.

### 3.4 Consumidores derivados

Criar helper único para remover somente anchors conhecidas antes de:

- preview da lista;
- FTS/`SessionKnowledgeIndex`;
- chunks de embedding/`MemoryChunkBuilder`.

Unknown comments e conteúdo escrito permanecem intactos.

### 3.5 Contexto de renderer

Introduzir `MeetingBlockContext` com:

- `record`;
- `MeetingPlayer`;
- `envelope`;
- `loadingWaveform`;
- ações necessárias expostas pelo `AppModel`.

Plumbing explícito:

```text
SessionWorkspaceView
  → SessionWorkspacePane
    → MemoryNoteEditor
      → MarkdownBlockEditor
        → MeetingBlock renderer
```

- Contexto é opcional para written notes sem reunião.
- Slash menu mostra meeting blocks apenas quando existe contexto compatível.
- `HistorySessionDetailView` e qualquer outro caller de `MemoryNoteEditor` entram no
  inventário antes da mudança de initializer.

### 3.6 Testes do PR 3

`CueMeTests/MarkdownBlockDocumentTests.swift`:

- round-trip dos cinco kinds;
- unknown anchor lossless;
- Backspace após embedded block preserva texto;
- transform de texto não perde conteúdo;
- singleton/duplicate;
- reorder/remove;
- body delimiters não colidem;
- external deletion permanece deletada;
- migração roda uma vez;
- opening sem edição não reescreve o Markdown;
- anchors não entram em preview/FTS/embedding.

Filesystem integration:

- `note.md → SessionStore → reload → note.md`;
- frontmatter de version round-trip;
- rebuild dos índices mantém conteúdo e ignora anchors.

Atualizar ADR index, `docs/ARCHITECTURE.md` e `docs/ABSTRACTIONS.md` no mesmo PR.

---

## PR 4 — Documento único de reunião

### 4.1 TDD e fixture

Estender `UITestFixtures.memory` com uma reunião sintética que tenha:

- `hasAudio: true`, mas sem depender de arquivo real;
- participantes em inglês;
- transcript final;
- minutes/topics;
- decisions/open questions com evidence;
- takeaways com owner/evidence;
- coach cards e feedback;
- `markdownBody` com a stack de anchors.

O Recording block deve ter estado degradado determinístico quando
`containsRecording == true` e `player.isReady == false`.

Testes E2E:

- abrir a reunião e encontrar masthead + blocos no tab Document;
- navegar Transcript/Minutes e voltar ao Document;
- inserir/reordenar/remover bloco por `/`;
- editar decision/open question/takeaway inline;
- evidence seek;
- add/delete;
- follow-up;
- persistir dentro do mesmo launch.

Persistência entre launches fica no teste filesystem: a fixture é reinjetada a cada launch.

### 4.2 Flip do tab `Document`

- `documentTab` passa a ser `.note` para qualquer `SessionOrigin`.
- `SessionWorkspacePane(.note)` recebe `MeetingBlockContext`.
- `SessionReviewPane` permanece temporariamente como tab secundário/fallback até a matriz de
  paridade abaixo estar verde.
- Não criar `ReviewDocument`.

### 4.3 Renderers compartilhados

Criar `CueMe/Views/MeetingBlocks/`:

#### `RecordingBlock`

- Header `RECORDING · BOTH SIDES`, codec/duração quando disponíveis.
- `MeetingPlayer` + waveform; fallback estável sem arquivo.
- Corrigir barras não tocadas invisíveis e trocar playhead legado por `Theme.amber`.
- Identifiers próprios para header/play/fallback.

#### `CoachCuesBlock`

- Colapsado por default no pós-call.
- Carousel local baseado em `record.coachCards`; não usar navegação do buffer live.
- Mostrar `✓ used` quando feedback é helpful.
- Mostrar `cue at mm:ss` derivado de `card.ts`, nunca `used at`.
- Preservar `note.coach-cues`.

#### `TranscriptBlock`

- Speaker gutter, timestamps e tradução.
- Seek relativo a `record.audioTimelineStart`.
- Highlight now-playing e provenance/edited state.
- Empty/error states determinísticos.

#### `MinutesBlock`

- Overview e topics editáveis.
- Decisions e open questions como linhas próprias; não tentar join inexistente com
  `MeetingTopic`.
- Cada linha mantém `TextField` sempre presente, `review.item.<uuid>`, `EvidenceButton`,
  accessibility value, add/delete e save/onSubmit.
- Follow-up continua campo editável dentro do documento.

#### `ActionItemsBlock`

- Toggle/edit/owner/evidence/add/delete.
- Preservar ações atuais de `EditableTakeawayRow`.

### 4.4 Matriz de paridade obrigatória

Antes de deixar `Document` como primary:

| Capacidade atual | Novo bloco/host |
|---|---|
| Edit overview/topic | `MinutesBlock` |
| Add/edit/delete decision | `MinutesBlock` |
| Add/edit/delete open question | `MinutesBlock` |
| Evidence decision/question | `MinutesBlock` |
| Toggle/edit/delete takeaway | `ActionItemsBlock` |
| Evidence takeaway | `ActionItemsBlock` |
| Editable follow-up | `MinutesBlock` ou bloco dedicado |
| Regenerate + model picker | header `Export/Generate` |
| Generate follow-up formats | header `Export/Generate` |
| Post-processing error | banner no documento |
| Session health | disclosure no final |
| Coach history | `CoachCuesBlock` |

Tipos usados por `SessionSummaryPane`, `SessionTakeawaysPane` e
`LiveUtilityControls` não viram `private` nem são removidos enquanto houver consumers.

### 4.5 Verificação do PR 4

- Todos os E2E existentes e o novo cenário passam.
- `Document` não aponta para `.review`.
- Não há dois renderers novos para a mesma superfície.
- External anchor deletion continua respeitada.
- Visual compare note/review light/dark.
- `sentrux check . && sentrux gate .`.

---

## PR 5 — Coach herói e live

### 5.1 TDD

Cobrir antes do restyle:

- `coach.guide`, previous/next live, used/copy/pin e feedback.
- `live.note`, `live.note.input`, `live.note.submit`.
- `live.stop` e stop passivo.
- memory drawer/past notes.
- manual Ask via `app.manualInput` + `app.ask()`.
- health identifiers continuam únicos.

### 5.2 Coach herói

- Extrair `CoachHeroCard` para o live.
- Card mint, Literata no conteúdo, Hanken no chrome, mantendo `coach.guide`.
- Criar styling de highlight específico do coach; não alterar silenciosamente o caller de
  transcript em `Highlighter.translation`.
- Keyterms mudam apenas cor para `mintDeep`, sem tamanho/peso divergente do texto.
- `Used`, Copy, Pin e feedback usam ações existentes.

### 5.3 Live layout

- Main column centrada, max width 660, coach como hero.
- Minutes dentro da coluna, com empty/loading state em vez de desaparecer.
- Ask mid-call ligado a `manualInput`/`ask`.
- Transcript rail com expansão e entrada para `LiveMemoryDrawer`.
- Memory drawer não interrompe gravação.

### 5.4 Transporte

- Clock + meter de níveis atuais de mic/system.
- Preservar `LiveNoteButton`; não duplicar um TextField dentro de `Menu`.
- Overflow contém apenas ações reais, como Silence coach.
- `Stop & save` continua ação primária.
- Não incluir Pause, Mark this moment ou waveform histórico falso.
- `LiveTransportBar` passivo também oferece stop.

### 5.5 Verificação do PR 5

- E2E live completo e passivo.
- Nenhuma ação visível é no-op.
- `coach.guide` e `live.note*` permanecem na árvore de acessibilidade.
- Compare frame-live light/dark.

---

## PR 6 — Copy, token cleanup, pixel polish e docs

### 6.1 Copy

Padronizar em inglês somente superfícies do redesign:

- `ProjectTreeColumn`, `NoteListColumn`, headers/masthead;
- `MemoryNoteEditor`/blank note;
- meeting blocks/review;
- `AskCueMeBar`, `LiveMemoryDrawer`, `LiveNoteView`, coach;
- slash menu;
- `SessionLaunchView`, preservando `home.*`.

Atualizar asserts por copy no mesmo commit. Preflight, About e sheets ficam fora.

### 6.2 `SessionLaunchView`

- Manter o comportamento atual de launch e os identifiers
  `home.new-note`, `home.journal`, `home.record`, `home.profile.*`.
- Restyle com `Theme`/`.ui`/`.read` e copy em inglês.
- Não transformar launch em criação automática de nota nesta rodada.

### 6.3 Inventário de tokens

Nas superfícies tocadas, remover aliases legados:

- `Theme.cyan`;
- `panelRaised`;
- `divider`;
- `interactive`;
- `glassPanel`;
- `brand` decorativo.

Não fazer refactor amplo em telas fora do redesign. Separar bugfix visual de refactor
oportunista.

### 6.4 Pixel review

Comparar lado a lado:

- `frame-note.png`;
- `frame-review.png`;
- `frame-live.png`;
- `frame-blank.png`.

Matriz obrigatória:

- light/dark;
- janela normal e menor largura suportada;
- empty/loading/error;
- live/preparing/stopping;
- hover/focus/keyboard;
- reduced motion quando aplicável.

Regras:

- violeta = seleção/ação primária;
- mint = coach;
- âmbar = live/gravação;
- `amberText` para texto pequeno sobre papel;
- backgrounds limitados a `canvas/tree/list/paper`;
- sem texto interno, stack trace, URL interna ou env var em copy.

### 6.5 Docs finais

- Garantir ADR/index atualizados pelo PR 3.
- Consolidar `docs/ARCHITECTURE.md` e `docs/ABSTRACTIONS.md`:
  - Document único no block editor;
  - meeting block anchors + sidecar projections;
  - saída do `HeaderBar`;
  - `Views/MeetingBlocks/`;
  - live layout.

---

## Verificação de cada PR

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -only-testing:CueMeUITests test
sentrux check .
sentrux gate .
```

Além disso:

- diff sem secrets, paths absolutos exportados ou copy interna;
- fixtures sintéticas e isoladas;
- nenhuma mudança em `.pbxproj` para arquivos novos: o projeto usa synchronized file group;
- Conventional Commit por PR;
- docs/ADR no mesmo commit da decisão estrutural;
- CI verde antes de avançar ao PR seguinte.

---

## Plan Review

Revisado em 2026-07-27 via refine-plan, usando o contexto da sessão Claude
`da3be6fd-d3ba-414a-bc71-c70c8426118b` e validação adversarial contra o codebase real.

### Resumo

- Críticos: 5 encontrados, 5 resolvidos no plano.
- Recomendados: 4/4 aceitos.
- Nice-to-have: 0/2 incluídos.

### Decisões

- **Aceito — renderer único:** `MarkdownBlockEditor` vira a superfície Document de todas as
  notas; nenhum `ReviewDocument` paralelo.
- **Aceito — lifecycle seguro dos anchors:** gramática formal, version marker, migração
  única, respeito a remoção externa, limpeza de índices e testes de data loss.
- **Aceito — migração completa do HeaderBar:** capacidade, shortcut e accessibility contract
  ganham novo host antes da remoção.
- **Aceito — contratos das fases 2/6:** tabs, rename, source mode e primeiro editor permanecem
  funcionais durante o restyle.
- **Aceito — paridade do review:** evidence, add/delete, follow-up, erros e edição permanecem
  acessíveis no documento.
- **Aceito — árvore e live sintético:** usar `history`, namespace `tree.note.*` e
  `activeProjectID`.
- **Aceito — fixtures executáveis:** áudio metadata-only, participantes sintéticos, anchors,
  review/evidence e teste filesystem para reload.
- **Aceito — fidelidade limitada a capacidades reais:** sem Pause, Mark this moment,
  terceiro participante inventado, rolling waveform falso ou used timestamp inexistente.
- **Aceito — governança por PR:** TDD/E2E/docs/Sentrux acompanham cada mudança, não uma fase
  tardia.
- **Rejeitado por padrão — micro-geometria adicional:** ajustes de margem negativa/handles
  além do necessário para reproduzir os frames ficam para o pixel review.
- **Rejeitado por padrão — refactor amplo de tokens:** cleanup fica restrito às superfícies
  do redesign; não varrer telas fora do escopo.

### Como executar

> **Importante:** o botão "Build" do Cursor usa um executor genérico. Para o fluxo completo
> de TDD, commits, code review e CI, use `/run-plan`.

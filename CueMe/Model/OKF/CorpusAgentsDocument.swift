import Foundation

/// The operational schema that travels with the corpus, so an agent pointed at
/// the folder can work it without CueMe.
///
/// Written **only when absent, and never overwritten**: like the reference OKF
/// wiki template, this file is expected to evolve with the user, and
/// regenerating it would erase their edits. It is not part of the bundle and
/// carries no frontmatter. Golden: `specs/okf-corpus/contracts/corpus-agents.md`.
enum CorpusAgentsDocument {
    static let content = """
    # Corpus CueMe — schema operacional

    Este diretório é um bundle Open Knowledge Format v0.2. Só existe uma entidade: a
    nota. Projeto é uma nota. Pessoa é uma nota. Notas aninham em subníveis
    ilimitados.

    ## Estrutura

    - `<slug>.md` é uma nota. A pasta irmã `<slug>/` existe apenas quando a nota tem
      filhas ou material capturado.
    - `<slug>/raw/` guarda o que foi capturado: `transcript.md`, áudio, `attachments/`.
    - Nomes reservados: `index.md` e `log.md` em qualquer nível, `raw` dentro da pasta
      de uma nota, `AGENTS.md` na raiz.
    - Hierarquia é o caminho. Não existe campo de pai no frontmatter — mover a pasta
      move a nota.

    ## Frontmatter

    Todo `.md` não reservado começa com frontmatter YAML e um `type` não vazio.
    `type` em uso: `Note`, `Transcript`. Reservados: `Concept`, `Synthesis`,
    `Comparison`, `Source Summary`.

    Chaves OKF: `title`, `description`, `tags`, `created_at`, `updated_at`,
    `generated`, `sources`. Chaves específicas do CueMe usam o prefixo `x_cueme_`.
    Preserve chaves que você não conhece.

    ## Corpo

    Seções são delimitadas por marcadores `<!-- cueme:<nome> -->` na coluna 0. O
    título logo abaixo é decoração e é regerado — o marcador é que identifica a seção.
    Itens carregam id estável num comentário `<!--cueme {…}-->` no fim da linha.
    Preserve esses comentários; sem eles o item é tratado como novo.

    ## O que você pode e não pode

    - **Pode**: editar título, corpo, ata, decisões, pendências e links; criar notas;
      aninhar; corrigir uma fala pontual da transcrição.
    - **Não pode**: reescrever `raw/` em massa. É captura, não conhecimento. Uma
      correção pontual é legítima e preserva a trilha de auditoria; uma reescrita
      gerada por IA destrói o registro do que foi dito.
    - **Não pode**: reescrever `log.md`. É append-only e as entradas antigas são
      imutáveis.

    ## Operações

    Contrato-alvo, ainda não implementado pelo app — descrito aqui para quem operar o
    corpus por fora.

    ### INGEST
    Ao processar uma fonte nova: leia sem modificar, crie ou atualize as notas
    afetadas, preencha o frontmatter, ligue as notas relacionadas, atualize os
    `index.md` do escopo afetado e registre em `log.md`.

    ### QUERY
    Ao responder uma pergunta: leia `index.md` da raiz, navegue pelos índices e links
    antes de buscar amplo, cite as fontes. Quando a resposta tiver valor durável,
    incorpore como nota.

    ### LINT
    Periodicamente verifique: frontmatter parseável e `type` não vazio em todo `.md`
    não reservado; `index.md` e `log.md` só com seus significados reservados; pasta
    sem nota irmã; links internos quebrados; notas órfãs sem link de entrada;
    contradições entre notas; afirmações superadas por fonte mais recente; conceito
    citado sem nota própria; índices desatualizados.

    """
}

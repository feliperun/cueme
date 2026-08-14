#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6.0"]
# ///
"""One-shot migration from the pre-OKF Session Archive (session.json + note.md
+ knowledge-entities.json) to an OKF v0.2 corpus.

Runs once, outside the app (ADR 0043 / ADR 0049). Never writes to --source.
Exits 0 only if both independent verify checks (re-read + count
reconciliation) pass with zero mismatches.

See specs/okf-corpus/tasks/T020-migration-script.md and design.md sections
1, 3 and 4 for the authoritative format description.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import tempfile
import unicodedata
from dataclasses import dataclass, field
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

import yaml

# ============================================================================
# Constants
# ============================================================================

RESERVED_STEMS = {"index", "log", "agents"}
PRODUCER = "cueme/migrate-okf"

CUEME_MARKER_START_RE = re.compile(r"^\\*<!--\s?cueme")
CUEME_MARKER_UNESCAPE_RE = re.compile(r"^\\+<!--\s?cueme")
UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

SECTION_ORDER = [
    "minutes", "takeaways", "decisions", "open-questions",
    "follow-up", "notes", "coach", "artifacts", "sources",
]

MODE_LABELS = {
    "interview": "Entrevista",
    "sales": "Vendas",
    "difficult": "Conversa difícil",
    "meeting": "Reunião assistida",
    "recording": "Somente gravação",
    "custom": "Custom",
}

DEFAULT_PARTICIPANT_NAMES = {"self": "Você", "other": "Interlocutor"}

COUNT_KEYS = [
    "notas", "turnos", "pendencias", "decisoes", "questoes",
    "anotacoes", "artefatos", "topicos", "evidencias", "anexos", "anexos_bytes",
]

CORPUS_AGENTS_MD = """# Corpus CueMe — schema operacional

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


# ============================================================================
# YAML emission — forced double-quote style for dates/paths/URIs/fragments
# ============================================================================

class QuotedStr(str):
    """A string that must always render double-quoted (dates, paths, URIs,
    fragments — design.md §3 quoting policy). Ordinary text relies on
    PyYAML's own resolver-mismatch detection to quote ambiguous values."""


class IndentedDumper(yaml.SafeDumper):
    def increase_indent(self, flow=False, indentless=False):  # noqa: FBT002
        return super().increase_indent(flow, False)


def _represent_quoted(dumper: yaml.SafeDumper, data: QuotedStr):
    return dumper.represent_scalar("tag:yaml.org,2002:str", str(data), style='"')


IndentedDumper.add_representer(QuotedStr, _represent_quoted)


def render_frontmatter_yaml(fm: dict) -> str:
    return yaml.dump(
        fm, Dumper=IndentedDumper, sort_keys=False,
        default_flow_style=False, allow_unicode=True, width=1_000_000,
    )


def render_note_md(frontmatter: dict, body: str) -> str:
    yaml_text = render_frontmatter_yaml(frontmatter).rstrip("\n")
    return f"---\n{yaml_text}\n---\n\n{body}".rstrip("\n") + "\n"


def split_frontmatter(text: str) -> tuple[dict, str]:
    lines = text.split("\n")
    if not lines or lines[0] != "---":
        raise ValueError("missing frontmatter delimiter")
    try:
        close = lines[1:].index("---") + 1
    except ValueError as exc:
        raise ValueError("unterminated frontmatter") from exc
    fm_text = "\n".join(lines[1:close])
    frontmatter = yaml.safe_load(fm_text) or {}
    body_lines = lines[close + 1:]
    if body_lines and body_lines[0] == "":
        body_lines = body_lines[1:]
    return frontmatter, "\n".join(body_lines)


# ============================================================================
# Small utilities: slug, dates, doubles, escaping, uuids
# ============================================================================

def slugify(value: str, limit: int = 54) -> str:
    folded = unicodedata.normalize("NFKD", value or "")
    folded = "".join(c for c in folded if not unicodedata.combining(c))
    folded = folded.lower()
    slug = re.sub(r"[^a-z0-9]+", "-", folded).strip("-")
    slug = slug[:limit].strip("-")
    return slug or "nota"


def unique_slug(base: str, taken: set[str]) -> str:
    candidate = base if base not in RESERVED_STEMS else f"{base}-nota"
    n = 2
    original = candidate
    while candidate in taken:
        candidate = f"{original}-{n}"
        n += 1
    taken.add(candidate)
    return candidate


def parse_old_date(value: str) -> datetime:
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def format_new_date(dt: datetime) -> str:
    dt = dt.astimezone(timezone.utc)
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{dt.microsecond // 1000:03d}Z"


def quantize3(value) -> float | None:
    return None if value is None else round(float(value), 3)


def format_double(value: float) -> str:
    return repr(float(value))


def uid(value: str | None) -> str | None:
    """UUIDs are always lowercased on emission into the new format (design.md
    §3: 'UUIDs em minúsculas'). Never applied to values used for filesystem
    lookups against the old archive, which must keep their original casing."""
    return value.lower() if value else value


def escape_line(line: str) -> str:
    return "\\" + line if CUEME_MARKER_START_RE.match(line) else line


def unescape_line(line: str) -> str:
    return line[1:] if CUEME_MARKER_UNESCAPE_RE.match(line) else line


def escape_text(text: str) -> str:
    return "\n".join(escape_line(l) for l in text.split("\n"))


def unescape_text(text: str) -> str:
    return "\n".join(unescape_line(l) for l in text.split("\n"))


def today_local() -> date:
    return datetime.now().date()


def format_clock(seconds: float) -> str:
    total = max(0, int(seconds))
    hours, rem = divmod(total, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return f"{hours:02d}:{minutes:02d}:{secs:02d}"
    return f"{minutes:02d}:{secs:02d}"


def hash_tree(root: Path) -> str:
    h = hashlib.sha256()
    if not root.exists():
        return h.hexdigest()
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        h.update(str(path.relative_to(root)).encode("utf-8"))
        h.update(path.read_bytes())
    return h.hexdigest()


# ============================================================================
# Old format readers — session.json (tolerant decode) + note.md precedence
# ============================================================================
#
# Replicates CueMe/Model/SessionRecord.swift's `init(from decoder:)` (decode
# defaults) and CueMe/Model/NoteDocument.swift:35-59 `mergeCanonicalFields`
# (git history — the file was deleted from HEAD by the greenfield policy,
# ADR 0043). Verified empirically against the real Swift compiler that
# Dictionary<NonStringKey, Value> — [Speaker: String], [UUID: CoachFeedback]
# — encodes as a flat [key, value, key, value, ...] array, not a JSON object.

def _pairs_to_dict(flat_list) -> dict:
    it = iter(flat_list or [])
    return dict(zip(it, it))


def infer_note_kind(mode: str, origin: str) -> str:
    if origin == "written":
        return "note"
    if origin != "live":
        return "imported-audio"
    return {
        "interview": "interview", "sales": "sales", "difficult": "difficult-conversation",
        "meeting": "meeting", "recording": "recording", "custom": "custom",
    }.get(mode, "note")


def _normalized_labels(values: list[str]) -> list[str]:
    cleaned = {v.strip().lower()[:48] for v in values if v.strip()}
    return sorted(cleaned)


def _normalize_participant_names(raw: dict) -> dict:
    names = raw.get("participantNames")
    if isinstance(names, list):
        names = _pairs_to_dict(names)
    if isinstance(names, dict) and names:
        return names
    return dict(DEFAULT_PARTICIPANT_NAMES)


def _normalize_coach_feedback(raw: dict) -> dict:
    feedback = raw.get("coachFeedback")
    if isinstance(feedback, list):
        return _pairs_to_dict(feedback)
    return feedback if isinstance(feedback, dict) else {}


def _normalize_minutes(raw: dict) -> dict:
    minutes = raw.get("minutes")
    if minutes:
        return minutes
    overview = " ".join(raw.get("summaryBullets") or [])
    return {"overview": overview, "topics": []}


def read_session_json(path: Path) -> dict:
    raw = json.loads(path.read_text(encoding="utf-8"))
    mode = raw["mode"]
    origin = raw.get("origin", "live")
    ended_at = raw["endedAt"]
    display_title = raw.get("displayTitle")
    title_source_default = "fallback" if not display_title else "generated"

    return {
        "id": raw["id"],
        "startedAt": raw["startedAt"],
        "recordingStartedAt": raw.get("recordingStartedAt"),
        "endedAt": ended_at,
        "mode": mode,
        "training": raw.get("training", False),
        "conversationLang": raw["conversationLang"],
        "nativeLang": raw["nativeLang"],
        "goal": raw.get("goal", ""),
        "transcript": raw.get("transcript", []),
        "coachCards": raw.get("coachCards", []),
        "minutes": _normalize_minutes(raw),
        "participantNames": _normalize_participant_names(raw),
        "coachModel": raw.get("coachModel"),
        "summaryModel": raw.get("summaryModel"),
        "vocabulary": raw.get("vocabulary", {"keyterms": [], "replacements": {}}),
        "hasAudio": raw.get("hasAudio", False),
        "audioDuration": raw.get("audioDuration", 0),
        "diagnostics": raw.get("diagnostics", {"events": []}),
        "coachFeedback": _normalize_coach_feedback(raw),
        "notes": raw.get("notes", []),
        "takeaways": raw.get("takeaways", []),
        "origin": origin,
        "displayTitle": display_title,
        "review": raw.get("review", {"decisions": [], "openQuestions": [], "followUp": ""}),
        "artifacts": raw.get("artifacts", []),
        "projectID": raw.get("projectID"),
        "personIDs": raw.get("personIDs", []),
        "noteKind": raw.get("noteKind", infer_note_kind(mode, origin)),
        "markdownBody": raw.get("markdownBody", ""),
        "labels": _normalized_labels(raw.get("labels", [])),
        "attachments": raw.get("attachments", []),
        "titleSource": raw.get("titleSource", title_source_default),
        "modifiedAt": raw.get("modifiedAt", ended_at),
    }


KNOWN_NOTE_KINDS = {
    "note", "journal", "meeting", "interview", "sales",
    "difficult-conversation", "recording", "imported-audio", "custom",
}
KNOWN_TITLE_SOURCES = {"fallback", "generated", "user"}


def _unquote_json_ish(value: str) -> str:
    if value.startswith('"'):
        try:
            return json.loads(value)
        except json.JSONDecodeError:
            return value
    return value


def _parse_old_note_md(text: str) -> dict | None:
    """Mirrors NoteDocument.parse(_:) exactly: a naive line-based scan, not
    real YAML. Old note.md was never real YAML — see design.md's rationale
    for adding Yams (ADR 0044)."""
    lines = text.split("\n")
    if not lines or lines[0] != "---":
        return None
    try:
        close = lines[1:].index("---") + 1
    except ValueError:
        return None
    values: dict[str, str] = {}
    for line in lines[1:close]:
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        values[key.strip()] = _unquote_json_ish(value.strip())
    try:
        labels = json.loads(values.get("labels", "[]"))
    except json.JSONDecodeError:
        labels = []
    remainder = lines[close + 1:]
    body = ""
    if "<!-- cueme:body:start -->" in remainder:
        start = remainder.index("<!-- cueme:body:start -->")
        rest = remainder[start + 1:]
        if "<!-- cueme:body:end -->" in rest:
            end = rest.index("<!-- cueme:body:end -->")
            body = "\n".join(rest[:end]).strip("\n")
    return {"values": values, "labels": labels, "body": body}


def merge_canonical_fields(record: dict, note_md_path: Path) -> dict:
    """Replicates NoteDocument.mergeCanonicalFields(from:into:) precedence
    exactly: title, kind, title_source, project_id, labels, updated_at and
    the delimited body come from note.md and win over the JSON — even when
    note.md declares labels/body empty, they still unconditionally overwrite
    the JSON's values (constitution.md flags this as the highest-risk edge
    case: skipping it silently reverts every external edit)."""
    if not note_md_path.exists():
        return record
    try:
        text = note_md_path.read_text(encoding="utf-8")
    except OSError:
        return record
    parsed = _parse_old_note_md(text)
    if parsed is None:
        return record

    merged = dict(record)
    values = parsed["values"]

    title = values.get("title", "")
    if title:
        merged["displayTitle"] = title
    kind = values.get("kind")
    if kind in KNOWN_NOTE_KINDS:
        merged["noteKind"] = kind
    title_source = values.get("title_source")
    if title_source in KNOWN_TITLE_SOURCES:
        merged["titleSource"] = title_source
    if "project_id" in values:
        project_id = values["project_id"]
        merged["projectID"] = None if project_id == "null" else project_id
    merged["labels"] = parsed["labels"]
    merged["markdownBody"] = parsed["body"]
    updated_at = values.get("updated_at")
    if updated_at:
        try:
            parse_old_date(updated_at)
        except ValueError:
            pass
        else:
            merged["modifiedAt"] = updated_at
    return merged


def load_entities(path: Path) -> tuple[list[dict], list[dict]]:
    if not path.exists():
        return [], []
    payload = json.loads(path.read_text(encoding="utf-8"))
    return payload.get("projects") or [], payload.get("people") or []


# ============================================================================
# Item attribute codec — the <!--cueme {...}--> inline flow mapping (§4.2)
# ============================================================================
# A small, self-contained flow-mapping micro-format: one line, comma-
# separated `key: value` pairs, values either bare (uuid/enum/number/bool)
# or double-quoted (dates, text needing escaping). Not full YAML — deliberately
# constrained so writer and reader stay a trivially matched pair.

def _attr_scalar_needs_quote(s: str) -> bool:
    if s == "" or s != s.strip():
        return True
    if s[0] in "{}[]#&*!|>'\"%@`,":
        return True
    if re.search(r": |( #)", s):
        return True
    return False


def fmt_attr_scalar(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return format_double(value)
    if isinstance(value, QuotedStr):
        return json.dumps(str(value))
    s = str(value)
    return json.dumps(s) if _attr_scalar_needs_quote(s) else s


def render_attrs(pairs: list[tuple[str, Any]]) -> str:
    parts = []
    for key, value in pairs:
        if value is None:
            continue
        if isinstance(value, list):
            rendered = ", ".join(fmt_attr_scalar(v) for v in value)
            parts.append(f"{key}: [{rendered}]")
        else:
            parts.append(f"{key}: {fmt_attr_scalar(value)}")
    return "{" + ", ".join(parts) + "}"


def attrs_comment(pairs: list[tuple[str, Any]]) -> str:
    return f"<!--cueme {render_attrs(pairs)}-->"


def _split_attr_pairs(inner: str) -> list[tuple[str, str]]:
    tokens: list[str] = []
    current: list[str] = []
    depth = 0
    in_quotes = False
    i = 0
    while i < len(inner):
        c = inner[i]
        if in_quotes:
            current.append(c)
            if c == "\\" and i + 1 < len(inner):
                i += 1
                current.append(inner[i])
            elif c == '"':
                in_quotes = False
        elif c == '"':
            in_quotes = True
            current.append(c)
        elif c in "[{":
            depth += 1
            current.append(c)
        elif c in "]}":
            depth -= 1
            current.append(c)
        elif c == "," and depth == 0:
            tokens.append("".join(current))
            current = []
        else:
            current.append(c)
        i += 1
    if current:
        tokens.append("".join(current))
    pairs = []
    for token in tokens:
        if not token.strip():
            continue
        key, _, value = token.partition(":")
        pairs.append((key.strip(), value.strip()))
    return pairs


def _parse_attr_value(text: str):
    text = text.strip()
    if text.startswith('"'):
        return json.loads(text)
    if text.startswith("["):
        inner = text[1:-1].strip()
        return [] if not inner else [item.strip() for item in inner.split(",")]
    if text == "true":
        return True
    if text == "false":
        return False
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    try:
        return float(text)
    except ValueError:
        return text


def parse_attrs(raw: str) -> dict:
    raw = raw.strip()
    if raw.startswith("<!--cueme"):
        raw = raw[len("<!--cueme"):].strip()
    if raw.endswith("-->"):
        raw = raw[: -len("-->")].strip()
    if not (raw.startswith("{") and raw.endswith("}")):
        return {}
    inner = raw[1:-1].strip()
    return {key: _parse_attr_value(value) for key, value in _split_attr_pairs(inner)}


# ============================================================================
# Evidence dedup pool — design.md §3 "Deduplicates for free"
# ============================================================================
# The old model stores an independent MemoryEvidence copy per item citing it
# (each with its own fresh id). The new format has ONE sources[] entry per
# distinct (turn, timestamp, quote); every citing item gets a [^ev-<id>]
# footnote ref pointing at the first-seen (canonical) entry.

class EvidencePool:
    def __init__(self) -> None:
        self._by_key: dict[tuple, dict] = {}
        self._order: list[tuple] = []

    def register_many(self, evidence_list: list[dict]) -> list[str]:
        return [self.register(e) for e in evidence_list]

    def register(self, ev: dict) -> str:
        key = (uid(ev.get("turnID")), quantize3(ev["timestamp"]), ev["quote"])
        if key not in self._by_key:
            self._by_key[key] = ev
            self._order.append(key)
        canonical = self._by_key[key]
        return f"ev-{uid(canonical['id'])}"

    def sources(self) -> list[dict]:
        result = []
        for key in self._order:
            ev = self._by_key[key]
            turn_id = uid(ev.get("turnID"))
            resource = f"raw/transcript.md#t-{turn_id}" if turn_id else "raw/transcript.md"
            entry: dict[str, Any] = {
                "id": f"ev-{uid(ev['id'])}",
                "resource": QuotedStr(resource),
                "title": ev["quote"],
                "x_timestamp": quantize3(ev["timestamp"]),
            }
            if turn_id:
                entry["x_turn_id"] = turn_id
            result.append(entry)
        return sorted(result, key=lambda e: e["id"])

    def distinct_count(self) -> int:
        return len(self._order)


# ============================================================================
# Body section renderers (design.md §4)
# ============================================================================

def build_marker_block(marker_name: str, heading: str, content_lines: list[str]) -> list[str]:
    lines = [f"<!-- cueme:{marker_name} -->", heading]
    if content_lines:
        lines.append("")
        lines.extend(content_lines)
    return lines


def render_minutes(minutes: dict) -> list[str] | None:
    overview = (minutes.get("overview") or "").strip()
    topics = minutes.get("topics") or []
    if not overview and not topics:
        return None
    content: list[str] = []
    if overview:
        content.extend(escape_text(overview).split("\n"))
    for topic in topics:
        if content:
            content.append("")
        comment = attrs_comment([
            ("id", uid(topic["id"])),
            ("at", QuotedStr(format_new_date(parse_old_date(topic["updatedAt"])))),
        ])
        content.append(f"### {topic['title']} {comment}")
        content.append("")
        content.extend(escape_text(topic["summary"]).split("\n"))
    return build_marker_block("minutes", "## Ata", content)


def render_takeaways(takeaways: list[dict], pool: EvidencePool) -> list[str] | None:
    if not takeaways:
        return None
    content = []
    for item in takeaways:
        refs = pool.register_many(item.get("evidence") or [])
        text = escape_line(item["text"]) + "".join(f"[^{r}]" for r in refs)
        pairs: list[tuple[str, Any]] = [
            ("id", uid(item["id"])),
            ("at", QuotedStr(format_new_date(parse_old_date(item["createdAt"])))),
        ]
        if item.get("confidence") is not None:
            pairs.append(("confidence", quantize3(item["confidence"])))
        if item.get("assignee"):
            pairs.append(("assignee", item["assignee"]))
        if item.get("dueAt"):
            pairs.append(("due", QuotedStr(format_new_date(parse_old_date(item["dueAt"])))))
        checkbox = "x" if item.get("isDone") else " "
        content.append(f"- [{checkbox}] {text} {attrs_comment(pairs)}")
    return build_marker_block("takeaways", "## Pendências", content)


def render_review_items(items: list[dict], pool: EvidencePool) -> list[str]:
    lines = []
    for item in items:
        refs = pool.register_many(item.get("evidence") or [])
        text = escape_line(item["text"]) + "".join(f"[^{r}]" for r in refs)
        pairs: list[tuple[str, Any]] = [("id", uid(item["id"]))]
        if item.get("confidence") is not None:
            pairs.append(("confidence", quantize3(item["confidence"])))
        if item.get("supersedesID"):
            pairs.append(("supersedes", uid(item["supersedesID"])))
        lines.append(f"- {text} {attrs_comment(pairs)}")
    return lines


def render_follow_up(text: str) -> list[str] | None:
    text = (text or "").strip()
    if not text:
        return None
    return build_marker_block("follow-up", "## Follow-up", escape_text(text).split("\n"))


def render_session_notes(notes: list[dict]) -> list[str] | None:
    if not notes:
        return None
    ordered = sorted(notes, key=lambda n: n["timeOffset"])
    content = []
    for n in ordered:
        pairs: list[tuple[str, Any]] = [
            ("id", uid(n["id"])),
            ("t", quantize3(n["timeOffset"])),
            ("at", QuotedStr(format_new_date(parse_old_date(n["createdAt"])))),
        ]
        content.append(f"- {escape_line(n['text'])} {attrs_comment(pairs)}")
    return build_marker_block("notes", "## Anotações", content)


def _card_has_content(card: dict) -> bool:
    return bool(
        (card.get("guidePT") or "").strip()
        or (card.get("sayConversation") or "").strip()
        or (card.get("sayNative") or "").strip()
    )


def render_coach(cards: list[dict], started_at: datetime) -> list[str] | None:
    active = [c for c in cards if _card_has_content(c)]
    if not active:
        return None
    content: list[str] = []
    for card in active:
        if content:
            content.append("")
        ts = parse_old_date(card["ts"])
        clock = format_clock((ts - started_at).total_seconds())
        pairs: list[tuple[str, Any]] = [
            ("id", uid(card["id"])),
            ("ts", QuotedStr(format_new_date(ts))),
            ("kind", card["kind"]),
            ("severity", card["severity"]),
        ]
        keyterms = card.get("keytermsConversation") or []
        if keyterms:
            pairs.append(("keyterms", keyterms))
        content.append(f"### {clock} {attrs_comment(pairs)}")
        content.append("")
        guide = (card.get("guidePT") or "").strip()
        if guide:
            content.extend(escape_text(guide).split("\n"))
        extra = []
        say_conv = card.get("sayConversation")
        say_native = card.get("sayNative") or ""
        if say_conv:
            extra.append(f"<!--cueme:say-conv-->{escape_line(say_conv)}")
        if say_native:
            extra.append(f"<!--cueme:say-native-->{escape_line(say_native)}")
        if extra:
            if guide:
                content.append("")
            content.extend(extra)
    return build_marker_block("coach", "## Coach", content)


def render_artifacts(artifacts: list[dict]) -> list[str] | None:
    if not artifacts:
        return None
    content: list[str] = []
    for art in artifacts:
        if content:
            content.append("")
        pairs: list[tuple[str, Any]] = [
            ("id", uid(art["id"])),
            ("kind", art["kind"]),
            ("at", QuotedStr(format_new_date(parse_old_date(art["createdAt"])))),
        ]
        content.append(f"### {art['title']} {attrs_comment(pairs)}")
        content.append("")
        content.extend(escape_text(art["body"]).split("\n"))
    return build_marker_block("artifacts", "## Conteúdo gerado", content)


def render_sources_section(sources: list[dict]) -> list[str] | None:
    if not sources:
        return None
    return ["<!-- cueme:sources -->", *[f"[^{s['id']}]: {s['title']}" for s in sources]]


def render_note_body(title: str, user_body: str, sections: dict[str, list[str] | None]) -> str:
    lines = [f"# {title}", ""]
    stripped = (user_body or "").strip()
    if stripped:
        lines.extend(escape_text(stripped).split("\n"))
        lines.append("")
    for name in SECTION_ORDER:
        block = sections.get(name)
        if not block:
            continue
        lines.extend(block)
        lines.append("")
    text = "\n".join(lines)
    return text.rstrip("\n") + "\n"


# ============================================================================
# raw/transcript.md (design.md §4.11)
# ============================================================================

def build_transcript(record: dict, note_id: str, note_title: str) -> tuple[dict, str, int] | None:
    finals = [t for t in record["transcript"] if t.get("isFinal")]
    if not finals:
        return None
    started_at = parse_old_date(record["startedAt"])
    audio_start = (
        parse_old_date(record["recordingStartedAt"]) if record.get("recordingStartedAt") else started_at
    )
    participant_names = record["participantNames"]

    lines = ["<!-- cueme:transcript -->", "# Transcrição", ""]
    for i, turn in enumerate(finals):
        if i:
            lines.append("")
        speaker = turn["speaker"]
        name = participant_names.get(speaker) or DEFAULT_PARTICIPANT_NAMES.get(speaker, speaker)
        ts = parse_old_date(turn["ts"])
        clock = format_clock((ts - audio_start).total_seconds())
        pairs: list[tuple[str, Any]] = [
            ("id", uid(turn["id"])),
            ("sp", speaker),
            ("ts", QuotedStr(format_new_date(ts))),
        ]
        if turn.get("sourceTurnID"):
            pairs.append(("src", uid(turn["sourceTurnID"])))
        if turn.get("editedAt"):
            pairs.append(("edited_at", QuotedStr(format_new_date(parse_old_date(turn["editedAt"])))))
        lines.append(f"**{name} · {clock}** {attrs_comment(pairs)}")
        lines.append(escape_line(turn["text"]))
        if turn.get("originalText"):
            lines.append(f"<!--cueme:orig-->{escape_line(turn['originalText'])}")
        if turn.get("translation"):
            lines.append(f"<!--cueme:tr-->{escape_line(turn['translation'])}")
    body = "\n".join(lines).rstrip("\n") + "\n"

    frontmatter: dict[str, Any] = {
        "type": "Transcript",
        "title": f"Transcrição — {note_title}",
        "description": f"Captura verbatim da sessão de {started_at.strftime('%d/%m/%Y')}.",
        "generated": {
            "by": PRODUCER,
            "at": QuotedStr(format_new_date(parse_old_date(record["modifiedAt"]))),
        },
        "x_cueme_note_id": uid(note_id),
        "x_cueme_started_at": QuotedStr(format_new_date(started_at)),
    }
    if participant_names:
        frontmatter["x_cueme_participant_names"] = dict(sorted(participant_names.items()))
    return frontmatter, body, len(finals)


# ============================================================================
# Frontmatter + raw asset planning for a migrated session note
# ============================================================================

def count_diagnostics(diagnostics: dict) -> tuple[int, int]:
    events = diagnostics.get("events") or []
    errors = sum(1 for e in events if e.get("kind") == "error")
    recoveries = sum(1 for e in events if e.get("kind") == "recovery")
    return errors, recoveries


def build_attachment_entries(attachments: list[dict]) -> list[dict]:
    entries = []
    for att in attachments:
        basename = Path(att["filename"]).name
        entries.append({
            "id": uid(att["id"]),
            "file": QuotedStr(f"raw/attachments/{basename}"),
            "kind": att["kind"],
            "added_at": QuotedStr(format_new_date(parse_old_date(att["addedAt"]))),
        })
    return sorted(entries, key=lambda e: e["id"])


def compute_title(record: dict) -> str:
    display = (record.get("displayTitle") or "").strip()
    if display:
        return display[:120]
    for line in record["transcript"]:
        if line.get("speaker") == "other" and line.get("isFinal"):
            text = (line.get("text") or "").strip()
            if text:
                return text[:80]
    mode_label = MODE_LABELS.get(record["mode"], record["mode"])
    return f"Treino · {mode_label}" if record.get("training") else mode_label


def _fm_core(record: dict, sources: list[dict], links: list[str]) -> dict:
    fm: dict[str, Any] = {"type": "Note", "title": compute_title(record)}
    goal = (record.get("goal") or "").strip()
    if goal:
        fm["description"] = goal
    tags = sorted(record.get("labels") or [])
    if tags:
        fm["tags"] = tags
    started_at = parse_old_date(record["startedAt"])
    modified_at = parse_old_date(record["modifiedAt"])
    fm["created_at"] = QuotedStr(format_new_date(started_at))
    fm["updated_at"] = QuotedStr(format_new_date(modified_at))
    fm["generated"] = {"by": PRODUCER, "at": QuotedStr(format_new_date(modified_at))}
    if sources:
        fm["sources"] = sources
    if links:
        fm["x_cueme_links"] = sorted(QuotedStr(l) for l in links)
    return fm


def _fm_session_meta(record: dict) -> dict:
    fm: dict[str, Any] = {
        "x_cueme_kind": record["noteKind"],
        "x_cueme_mode": record["mode"],
        "x_cueme_origin": record["origin"],
        "x_cueme_training": bool(record.get("training", False)),
        "x_cueme_title_source": record["titleSource"],
        "x_cueme_ended_at": QuotedStr(format_new_date(parse_old_date(record["endedAt"]))),
        "x_cueme_lang": {"conversation": record["conversationLang"], "native": record["nativeLang"]},
    }
    participant_names = record.get("participantNames") or {}
    if participant_names:
        fm["x_cueme_participant_names"] = dict(sorted(participant_names.items()))
    return fm


def _fm_models(record: dict) -> dict:
    models = {}
    if record.get("coachModel"):
        models["coach"] = record["coachModel"]
    if record.get("summaryModel"):
        models["summary"] = record["summaryModel"]
    return {"x_cueme_models": models} if models else {}


def _fm_audio(record: dict) -> dict:
    if not record.get("hasAudio"):
        return {}
    audio: dict[str, Any] = {"duration": quantize3(record.get("audioDuration") or 0)}
    if record.get("recordingStartedAt"):
        audio["recording_started_at"] = QuotedStr(
            format_new_date(parse_old_date(record["recordingStartedAt"]))
        )
    return {"x_cueme_audio": audio}


def _fm_transcript_and_attachments(record: dict, transcript_turns: int) -> dict:
    fm: dict[str, Any] = {}
    if transcript_turns:
        fm["x_cueme_transcript"] = {"file": QuotedStr("raw/transcript.md"), "turns": transcript_turns}
    attachments = build_attachment_entries(record.get("attachments") or [])
    if attachments:
        fm["x_cueme_attachments"] = attachments
    return fm


def _fm_vocabulary_and_feedback(record: dict) -> dict:
    fm: dict[str, Any] = {}
    vocabulary = record.get("vocabulary") or {}
    keyterms = sorted(vocabulary.get("keyterms") or [])
    replacements = vocabulary.get("replacements") or {}
    if keyterms or replacements:
        vocab_fm: dict[str, Any] = {}
        if keyterms:
            vocab_fm["keyterms"] = keyterms
        if replacements:
            vocab_fm["replacements"] = dict(sorted(replacements.items()))
        fm["x_cueme_vocabulary"] = vocab_fm
    coach_feedback = record.get("coachFeedback") or {}
    if coach_feedback:
        fm["x_cueme_coach_feedback"] = {uid(k): v for k, v in sorted(coach_feedback.items())}
    return fm


def build_session_note_frontmatter(
    record: dict, *, links: list[str], sources: list[dict], transcript_turns: int,
) -> dict:
    """Field order follows design.md §3 exactly: each helper appends a
    contiguous run of keys in spec order, and dict.update() preserves
    insertion order for new keys — so chaining the helpers below reproduces
    the required order without one long branch-heavy function."""
    fm = _fm_core(record, sources, links)
    fm.update(_fm_session_meta(record))
    fm.update(_fm_models(record))
    fm.update(_fm_audio(record))
    errors, recoveries = count_diagnostics(record.get("diagnostics") or {})
    fm["x_cueme_integrity"] = {"errors": errors, "recoveries": recoveries}
    fm.update(_fm_transcript_and_attachments(record, transcript_turns))
    fm.update(_fm_vocabulary_and_feedback(record))
    return fm


def plan_raw_assets(
    record: dict, session_dir: Path, legacy_audio_root: Path,
) -> tuple[list[tuple[Path, str]], int, int]:
    """Returns (list of (source_path, dest_relative_path_within_raw),
    legacy .caf file count, legacy-audio-directory files absorbed count)."""
    plan: list[tuple[Path, str]] = []
    caf_count = 0
    legacy_absorbed = 0
    seen: set[str] = set()

    def consider(path: Path, dest_rel: str, *, is_legacy: bool) -> None:
        nonlocal caf_count, legacy_absorbed
        if dest_rel in seen:
            return
        seen.add(dest_rel)
        plan.append((path, dest_rel))
        if path.suffix == ".caf":
            caf_count += 1
        if is_legacy:
            legacy_absorbed += 1

    for name in ("self.m4a", "other.m4a", "self.caf", "other.caf"):
        candidate = session_dir / name
        if candidate.exists():
            consider(candidate, name, is_legacy=False)

    legacy_dir = legacy_audio_root / record["id"]
    if legacy_dir.exists():
        for name in ("self.m4a", "other.m4a", "self.caf", "other.caf"):
            candidate = legacy_dir / name
            if candidate.exists():
                consider(candidate, name, is_legacy=True)

    for att in record.get("attachments") or []:
        source = session_dir / att["filename"]
        if source.exists():
            consider(source, f"attachments/{Path(att['filename']).name}", is_legacy=False)

    return plan, caf_count, legacy_absorbed


@dataclass
class BuiltNote:
    slug: str
    parent: str | None
    title: str
    description: str
    frontmatter: dict
    body: str
    raw_plan: list[tuple[Path, str]] = field(default_factory=list)
    transcript: tuple[dict, str] | None = None
    counts: dict = field(default_factory=dict)


def build_session_note(
    record: dict, *, session_dir: Path, legacy_audio_root: Path, links: list[str],
) -> BuiltNote:
    title = compute_title(record)
    pool = EvidencePool()

    sections: dict[str, list[str] | None] = {
        "minutes": render_minutes(record["minutes"]),
        "takeaways": render_takeaways(record["takeaways"], pool),
        "follow-up": render_follow_up(record["review"].get("followUp", "")),
        "notes": render_session_notes(record["notes"]),
        "coach": render_coach(record["coachCards"], parse_old_date(record["startedAt"])),
        "artifacts": render_artifacts(record["artifacts"]),
    }
    decisions_lines = render_review_items(record["review"]["decisions"], pool)
    sections["decisions"] = (
        build_marker_block("decisions", "## Decisões", decisions_lines) if decisions_lines else None
    )
    questions_lines = render_review_items(record["review"]["openQuestions"], pool)
    sections["open-questions"] = (
        build_marker_block("open-questions", "## Questões em aberto", questions_lines)
        if questions_lines else None
    )
    sources = pool.sources()
    sections["sources"] = render_sources_section(sources)

    transcript_result = build_transcript(record, record["id"], title)
    transcript_turns = transcript_result[2] if transcript_result else 0

    frontmatter = build_session_note_frontmatter(
        record, links=links, sources=sources, transcript_turns=transcript_turns,
    )
    body = render_note_body(title, record.get("markdownBody", ""), sections)
    raw_plan, caf_count, legacy_absorbed = plan_raw_assets(record, session_dir, legacy_audio_root)

    attachments = record.get("attachments") or []
    counts = {
        "takeaways": len(record["takeaways"]),
        "decisions": len(record["review"]["decisions"]),
        "open_questions": len(record["review"]["openQuestions"]),
        "notes": len(record["notes"]),
        "artifacts": len(record["artifacts"]),
        "topics": len(record["minutes"].get("topics") or []),
        "turns": transcript_turns,
        "evidence_distinct": pool.distinct_count(),
        "attachments": len(attachments),
        "attachment_bytes": sum(
            (session_dir / a["filename"]).stat().st_size
            for a in attachments if (session_dir / a["filename"]).exists()
        ),
        "caf_files": caf_count,
        "legacy_audio_absorbed": legacy_absorbed,
    }

    return BuiltNote(
        slug="", parent=None, title=title, description=(record.get("goal") or "").strip(),
        frontmatter=frontmatter, body=body, raw_plan=raw_plan,
        transcript=((transcript_result[0], transcript_result[1]) if transcript_result else None),
        counts=counts,
    )


def build_project_note(project: dict) -> BuiltNote:
    name = project["name"]
    created = parse_old_date(project["createdAt"])
    fm = {
        "type": "Note",
        "title": name,
        "created_at": QuotedStr(format_new_date(created)),
        "updated_at": QuotedStr(format_new_date(created)),
        "generated": {"by": PRODUCER, "at": QuotedStr(format_new_date(created))},
    }
    body = render_note_body(name, project.get("summary") or "", {})
    return BuiltNote(slug="", parent=None, title=name, description="", frontmatter=fm, body=body)


def build_person_note(person: dict, anchor: datetime) -> BuiltNote:
    name = person["name"]
    fm = {
        "type": "Note",
        "title": name,
        "created_at": QuotedStr(format_new_date(anchor)),
        "updated_at": QuotedStr(format_new_date(anchor)),
        "generated": {"by": PRODUCER, "at": QuotedStr(format_new_date(anchor))},
    }
    lines = []
    aliases = person.get("aliases") or []
    if aliases:
        lines.append(f"- Aliases: {', '.join(aliases)}")
    if person.get("role"):
        lines.append(f"- Papel: {person['role']}")
    if person.get("organization"):
        lines.append(f"- Organização: {person['organization']}")
    body = render_note_body(name, "\n".join(lines), {})
    return BuiltNote(slug=slugify(name), parent=None, title=name, description="", frontmatter=fm, body=body)


def build_orphan_stub(person_id: str, anchor: datetime) -> BuiltNote:
    short = uid(person_id)[:8]
    title = f"Pessoa {short}"
    fm = {
        "type": "Note",
        "title": title,
        "created_at": QuotedStr(format_new_date(anchor)),
        "updated_at": QuotedStr(format_new_date(anchor)),
        "generated": {"by": PRODUCER, "at": QuotedStr(format_new_date(anchor))},
        "x_cueme_orphan": True,
    }
    body = render_note_body(title, "", {})
    return BuiltNote(
        slug=f"pessoa-{short}", parent=None, title=title, description="", frontmatter=fm, body=body,
    )


def build_anchor_note(title: str, anchor: datetime) -> BuiltNote:
    fm = {
        "type": "Note",
        "title": title,
        "created_at": QuotedStr(format_new_date(anchor)),
        "updated_at": QuotedStr(format_new_date(anchor)),
        "generated": {"by": PRODUCER, "at": QuotedStr(format_new_date(anchor))},
    }
    body = render_note_body(title, "", {})
    return BuiltNote(slug="", parent=None, title=title, description="", frontmatter=fm, body=body)


# ============================================================================
# Reader — mirrors the writer's grammars, used only by the verify checks.
# This is a self-contained pair with the writer above (not the Swift
# reader, which does not exist yet at this point in the plan — T012).
# ============================================================================

MARKER_RE = re.compile(r"^<!-- cueme:([a-z-]+) -->$")
BLOCK_HEADER_RE = re.compile(r"^### (.*?) (<!--cueme \{.*\}-->)$")
CHECKBOX_ITEM_RE = re.compile(r"^- \[( |x)\] (.*?)(?: (<!--cueme \{.*\}-->))?$")
PLAIN_ITEM_RE = re.compile(r"^- (.*?)(?: (<!--cueme \{.*\}-->))?$")
FOOTNOTE_REF_RE = re.compile(r"\[\^(ev-[0-9a-fA-F-]{3,40})\]")
FOOTNOTE_DEF_RE = re.compile(r"^\[\^(ev-[0-9a-fA-F-]{3,40})\]: (.*)$")
TURN_HEADER_RE = re.compile(r"^\*\*(.+?) · (\d{2}:\d{2}(?::\d{2})?)\*\* (<!--cueme \{.*\}-->)$")


def split_body_sections(body: str) -> tuple[str, str, dict[str, list[str]]]:
    lines = body.split("\n")
    idx = 0
    h1 = ""
    if idx < len(lines) and lines[idx].startswith("# "):
        h1 = lines[idx][2:].strip()
        idx += 1
    if idx < len(lines) and lines[idx] == "":
        idx += 1
    user_lines = []
    while idx < len(lines) and not MARKER_RE.match(lines[idx]):
        user_lines.append(lines[idx])
        idx += 1
    user_body = "\n".join(user_lines).strip("\n")

    sections: dict[str, list[str]] = {}
    current_name: str | None = None
    current_lines: list[str] = []
    while idx < len(lines):
        m = MARKER_RE.match(lines[idx])
        if m:
            if current_name:
                sections[current_name] = current_lines
            current_name = m.group(1)
            current_lines = []
            idx += 1
            continue
        current_lines.append(lines[idx])
        idx += 1
    if current_name:
        sections[current_name] = current_lines
    return h1, user_body, sections


def strip_heading_and_blank(lines: list[str]) -> list[str]:
    if lines and lines[0].startswith("#"):
        rest = lines[1:]
        if rest and rest[0] == "":
            rest = rest[1:]
        return rest
    return lines


def _extract_refs_and_text(text_with_refs: str) -> tuple[str, list[str]]:
    refs = FOOTNOTE_REF_RE.findall(text_with_refs)
    text = unescape_line(FOOTNOTE_REF_RE.sub("", text_with_refs))
    return text, refs


def parse_checkbox_items(lines: list[str]) -> list[dict]:
    items = []
    for line in lines:
        if not line.strip():
            continue
        m = CHECKBOX_ITEM_RE.match(line)
        if not m:
            continue
        checkbox, text_with_refs, comment = m.groups()
        text, refs = _extract_refs_and_text(text_with_refs)
        items.append({
            "is_done": checkbox == "x", "text": text, "refs": refs,
            "attrs": parse_attrs(comment) if comment else {},
        })
    return items


def parse_plain_items(lines: list[str]) -> list[dict]:
    items = []
    for line in lines:
        if not line.strip():
            continue
        m = PLAIN_ITEM_RE.match(line)
        if not m:
            continue
        text_with_refs, comment = m.groups()
        text, refs = _extract_refs_and_text(text_with_refs)
        items.append({"text": text, "refs": refs, "attrs": parse_attrs(comment) if comment else {}})
    return items


def parse_blocks(lines: list[str]) -> tuple[str, list[dict]]:
    idx = 0
    preamble_lines = []
    while idx < len(lines) and not BLOCK_HEADER_RE.match(lines[idx]):
        preamble_lines.append(lines[idx])
        idx += 1
    preamble = "\n".join(preamble_lines).strip("\n")

    blocks: list[dict] = []
    label: str | None = None
    attrs: dict = {}
    body_lines: list[str] = []

    def flush() -> None:
        if label is not None:
            blocks.append({"label": label, "attrs": attrs, "body": "\n".join(body_lines).strip("\n")})

    while idx < len(lines):
        m = BLOCK_HEADER_RE.match(lines[idx])
        if m:
            flush()
            label, attrs, body_lines = m.group(1), parse_attrs(m.group(2)), []
            idx += 1
            continue
        body_lines.append(lines[idx])
        idx += 1
    flush()
    return preamble, blocks


def split_coach_block_body(body_text: str) -> tuple[str, str | None, str | None]:
    lines = body_text.split("\n") if body_text else []
    guide_lines, say_conv, say_native = [], None, None
    for line in lines:
        if line.startswith("<!--cueme:say-conv-->"):
            say_conv = unescape_line(line[len("<!--cueme:say-conv-->"):])
        elif line.startswith("<!--cueme:say-native-->"):
            say_native = unescape_line(line[len("<!--cueme:say-native-->"):])
        else:
            guide_lines.append(line)
    return "\n".join(guide_lines).strip("\n"), say_conv, say_native


def parse_sources_section(lines: list[str]) -> list[dict]:
    return [
        {"id": m.group(1), "title": m.group(2)}
        for line in lines if (m := FOOTNOTE_DEF_RE.match(line))
    ]


def parse_note_md(text: str) -> dict:
    frontmatter, body = split_frontmatter(text)
    h1, user_body, sections = split_body_sections(body)
    result: dict[str, Any] = {"frontmatter": frontmatter, "h1": h1, "user_body": unescape_text(user_body)}

    if "minutes" in sections:
        preamble, blocks = parse_blocks(strip_heading_and_blank(sections["minutes"]))
        result["minutes_overview"] = unescape_text(preamble)
        result["minutes_topics"] = blocks
    if "takeaways" in sections:
        result["takeaways"] = parse_checkbox_items(strip_heading_and_blank(sections["takeaways"]))
    if "decisions" in sections:
        result["decisions"] = parse_plain_items(strip_heading_and_blank(sections["decisions"]))
    if "open-questions" in sections:
        result["open_questions"] = parse_plain_items(strip_heading_and_blank(sections["open-questions"]))
    if "follow-up" in sections:
        result["follow_up"] = unescape_text(
            "\n".join(strip_heading_and_blank(sections["follow-up"])).strip("\n")
        )
    if "notes" in sections:
        result["notes"] = parse_plain_items(strip_heading_and_blank(sections["notes"]))
    if "coach" in sections:
        _, blocks = parse_blocks(strip_heading_and_blank(sections["coach"]))
        result["coach_cards"] = blocks
    if "artifacts" in sections:
        _, blocks = parse_blocks(strip_heading_and_blank(sections["artifacts"]))
        result["artifacts"] = blocks
    if "sources" in sections:
        result["sources"] = parse_sources_section(sections["sources"])
    return result


def parse_transcript_md(text: str) -> dict:
    frontmatter, body = split_frontmatter(text)
    lines = body.split("\n")
    idx = 0
    if idx < len(lines) and MARKER_RE.match(lines[idx]):
        idx += 1
    if idx < len(lines) and lines[idx].startswith("# "):
        idx += 1
    if idx < len(lines) and lines[idx] == "":
        idx += 1

    turns: list[dict] = []
    current: dict | None = None
    current_body: list[str] = []

    def flush() -> None:
        if current is None:
            return
        text_lines, orig, tr = [], None, None
        for line in current_body:
            if line.startswith("<!--cueme:orig-->"):
                orig = unescape_line(line[len("<!--cueme:orig-->"):])
            elif line.startswith("<!--cueme:tr-->"):
                tr = unescape_line(line[len("<!--cueme:tr-->"):])
            else:
                text_lines.append(line)
        current["text"] = unescape_line("\n".join(text_lines).strip("\n"))
        current["original_text"] = orig
        current["translation"] = tr
        turns.append(current)

    for line in lines[idx:]:
        m = TURN_HEADER_RE.match(line)
        if m:
            flush()
            name, clock, comment = m.groups()
            current = {"name": name, "clock": clock, **parse_attrs(comment)}
            current_body = []
            continue
        if current is not None:
            current_body.append(line)
    flush()
    return {"frontmatter": frontmatter, "turns": turns}


# ============================================================================
# Writing to the staging tree
# ============================================================================

def _note_path(root: Path, note: BuiltNote) -> Path:
    return root / (f"{note.parent}/{note.slug}.md" if note.parent else f"{note.slug}.md")


def _raw_dir(root: Path, note: BuiltNote) -> Path:
    return root / (f"{note.parent}/{note.slug}/raw" if note.parent else f"{note.slug}/raw")


def write_all(staging: Path, all_notes: list[BuiltNote]) -> None:
    for note in all_notes:
        note_path = _note_path(staging, note)
        note_path.parent.mkdir(parents=True, exist_ok=True)
        note_path.write_text(render_note_md(note.frontmatter, note.body), encoding="utf-8")
        if note.transcript or note.raw_plan:
            raw_dir = _raw_dir(staging, note)
            raw_dir.mkdir(parents=True, exist_ok=True)
            if note.transcript:
                fm, body = note.transcript
                (raw_dir / "transcript.md").write_text(render_note_md(fm, body), encoding="utf-8")
            for source_path, dest_rel in note.raw_plan:
                dest_path = raw_dir / dest_rel
                dest_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source_path, dest_path)


def write_indexes(staging: Path, all_notes: list[BuiltNote]) -> None:
    root_notes = [n for n in all_notes if n.parent is None]
    root_lines = ["---", 'okf_version: "0.2"', "---", "", "# Notas", ""]
    for n in sorted(root_notes, key=lambda x: x.title):
        entry = f"* [{n.title}]({n.slug}.md)"
        if n.description:
            entry += f" - {n.description}"
        root_lines.append(entry)
    (staging / "index.md").write_text("\n".join(root_lines).rstrip("\n") + "\n", encoding="utf-8")

    by_parent: dict[str, list[BuiltNote]] = {}
    for n in all_notes:
        if n.parent:
            by_parent.setdefault(n.parent, []).append(n)
    parent_titles = {n.slug: n.title for n in root_notes}
    for parent_slug, children in by_parent.items():
        lines = [f"# {parent_titles.get(parent_slug, parent_slug)}", ""]
        for n in sorted(children, key=lambda x: x.title):
            entry = f"* [{n.title}]({n.slug}.md)"
            if n.description:
                entry += f" - {n.description}"
            lines.append(entry)
        index_path = staging / parent_slug / "index.md"
        index_path.parent.mkdir(parents=True, exist_ok=True)
        index_path.write_text("\n".join(lines).rstrip("\n") + "\n", encoding="utf-8")


def write_log(staging: Path, migrated_count: int, on: date) -> None:
    lines = [
        "# Histórico do corpus", "", f"## {on.isoformat()}", "",
        f"- **Migração**: {migrated_count} notas importadas do arquivo anterior no formato OKF v0.2.",
    ]
    (staging / "log.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def dump_diagnostics(directory: Path, records: list[tuple[dict, Path]]) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    for record, _ in records:
        events = (record.get("diagnostics") or {}).get("events") or []
        (directory / f"{record['id']}.json").write_text(json.dumps(events, indent=2), encoding="utf-8")


def purge_semantic_index(source: Path) -> list[str]:
    """Application Support keeps the semantic-search cache as a sibling of
    the Session Archive root (`<…CueMe>/Memory/memory.sqlite3`) — it is a
    derived index, not part of --source, and rebuilds on first search."""
    removed = []
    memory_dir = source.parent / "Memory"
    for name in ("memory.sqlite3", "memory.sqlite3-wal", "memory.sqlite3-shm"):
        candidate = memory_dir / name
        if candidate.exists():
            candidate.unlink()
            removed.append(str(candidate))
    return removed


def discover_session_dirs(source: Path) -> list[Path]:
    return sorted({p.parent for p in source.rglob("session.json")})


# ============================================================================
# Verify check #1 — re-read: parse every written .md back and compare
# field-by-field (never dict ==) against what was intended to be written.
# ============================================================================

NOTE_FIELDS_TO_COMPARE = [
    "type", "title", "description", "tags",
    "x_cueme_kind", "x_cueme_mode", "x_cueme_origin", "x_cueme_training",
    "x_cueme_title_source", "x_cueme_ended_at",
]


def reread_check(staging: Path, all_notes: list[BuiltNote]) -> list[str]:
    mismatches = []
    for note in all_notes:
        note_path = _note_path(staging, note)
        text = note_path.read_text(encoding="utf-8")
        try:
            actual_fm, actual_body = split_frontmatter(text)
        except ValueError as exc:
            mismatches.append(f"{note_path}: unparsable frontmatter ({exc})")
            continue
        for field_name in NOTE_FIELDS_TO_COMPARE:
            expected = note.frontmatter.get(field_name)
            if isinstance(expected, QuotedStr):
                expected = str(expected)
            actual = actual_fm.get(field_name)
            if expected != actual:
                mismatches.append(f"{note_path} field {field_name}: expected={expected!r} actual={actual!r}")
        if not actual_body.startswith(f"# {note.title}"):
            mismatches.append(f"{note_path}: H1 mismatch (expected '# {note.title}')")
        if note.transcript:
            transcript_path = _raw_dir(staging, note) / "transcript.md"
            if not transcript_path.exists():
                mismatches.append(f"{note_path}: expected raw/transcript.md, not found")
    return mismatches


# ============================================================================
# Verify check #2 — count reconciliation: lido -> escrito -> relido
# ============================================================================

def count_from_records(
    records_with_dirs: list[tuple[dict, Path]],
    projects: list[dict],
    people: list[dict],
    orphan_ids: set[str],
    has_pessoas_anchor: bool,
) -> dict[str, int]:
    counts = dict.fromkeys(COUNT_KEYS, 0)
    counts["notas"] = (
        len(records_with_dirs) + len(projects) + len(people) + len(orphan_ids)
        + 1 + (1 if has_pessoas_anchor else 0)
    )
    for record, session_dir in records_with_dirs:
        pool = EvidencePool()
        for t in record["takeaways"]:
            pool.register_many(t.get("evidence") or [])
        for d in record["review"]["decisions"]:
            pool.register_many(d.get("evidence") or [])
        for q in record["review"]["openQuestions"]:
            pool.register_many(q.get("evidence") or [])
        counts["turnos"] += sum(1 for t in record["transcript"] if t.get("isFinal"))
        counts["pendencias"] += len(record["takeaways"])
        counts["decisoes"] += len(record["review"]["decisions"])
        counts["questoes"] += len(record["review"]["openQuestions"])
        counts["anotacoes"] += len(record["notes"])
        counts["artefatos"] += len(record["artifacts"])
        counts["topicos"] += len(record["minutes"].get("topics") or [])
        counts["evidencias"] += pool.distinct_count()
        attachments = record.get("attachments") or []
        counts["anexos"] += len(attachments)
        for att in attachments:
            path = session_dir / att["filename"]
            if path.exists():
                counts["anexos_bytes"] += path.stat().st_size
    return counts


def count_from_built(all_notes: list[BuiltNote]) -> dict[str, int]:
    counts = dict.fromkeys(COUNT_KEYS, 0)
    counts["notas"] = len(all_notes)
    for note in all_notes:
        c = note.counts
        if not c:
            continue
        counts["turnos"] += c.get("turns", 0)
        counts["pendencias"] += c.get("takeaways", 0)
        counts["decisoes"] += c.get("decisions", 0)
        counts["questoes"] += c.get("open_questions", 0)
        counts["anotacoes"] += c.get("notes", 0)
        counts["artefatos"] += c.get("artifacts", 0)
        counts["topicos"] += c.get("topics", 0)
        counts["evidencias"] += c.get("evidence_distinct", 0)
        counts["anexos"] += c.get("attachments", 0)
        counts["anexos_bytes"] += c.get("attachment_bytes", 0)
    return counts


def _reread_frontmatter(text: str) -> dict | None:
    try:
        frontmatter, _ = split_frontmatter(text)
    except ValueError:
        return None
    return frontmatter


def _reread_attachment_bytes(path: Path, attachments: list[dict]) -> int:
    total = 0
    for att in attachments:
        file_rel = att.get("file")
        if not file_rel:
            continue
        att_path = path.parent / path.stem / file_rel
        if att_path.exists():
            total += att_path.stat().st_size
    return total


def _accumulate_note_counts(counts: dict[str, int], path: Path, text: str, frontmatter: dict) -> None:
    counts["notas"] += 1
    parsed = parse_note_md(text)
    counts["pendencias"] += len(parsed.get("takeaways") or [])
    counts["decisoes"] += len(parsed.get("decisions") or [])
    counts["questoes"] += len(parsed.get("open_questions") or [])
    counts["anotacoes"] += len(parsed.get("notes") or [])
    counts["artefatos"] += len(parsed.get("artifacts") or [])
    counts["topicos"] += len(parsed.get("minutes_topics") or [])
    counts["evidencias"] += len(frontmatter.get("sources") or [])
    attachments = frontmatter.get("x_cueme_attachments") or []
    counts["anexos"] += len(attachments)
    counts["anexos_bytes"] += _reread_attachment_bytes(path, attachments)


def count_from_reread(staging: Path) -> dict[str, int]:
    counts = dict.fromkeys(COUNT_KEYS, 0)
    for path in staging.rglob("*.md"):
        if path.name in ("index.md", "log.md", "AGENTS.md"):
            continue
        text = path.read_text(encoding="utf-8")
        frontmatter = _reread_frontmatter(text)
        if frontmatter is None:
            continue
        doc_type = frontmatter.get("type")
        if doc_type == "Transcript":
            counts["turnos"] += len(parse_transcript_md(text)["turns"])
        elif doc_type == "Note":
            _accumulate_note_counts(counts, path, text, frontmatter)
    return counts


def compare_counts(loaded: dict, written: dict, reread: dict) -> list[str]:
    mismatches = []
    for key in COUNT_KEYS:
        values = {"loaded": loaded.get(key, 0), "written": written.get(key, 0), "reread": reread.get(key, 0)}
        if len(set(values.values())) > 1:
            mismatches.append(f"{key}: {values}")
    return mismatches


def render_report_table(
    all_notes: list[BuiltNote], session_notes: list[BuiltNote],
    projects: list[dict], people: list[dict], orphan_count: int,
) -> str:
    return "\n".join([
        "OKF migration report",
        f"  notes written          : {len(all_notes)}",
        f"  sessions migrated      : {len(session_notes)}",
        f"  projects               : {len(projects)}",
        f"  people (catalogued)    : {len(people)}",
        f"  orphan person stubs    : {orphan_count}",
        f"  legacy audio absorbed  : {sum(n.counts.get('legacy_audio_absorbed', 0) for n in session_notes)}",
        f"  legacy .caf files      : {sum(n.counts.get('caf_files', 0) for n in session_notes)}",
        "Re-read check: field-by-field explicit comparison (never dict ==).",
        "Count reconciliation check: lido -> escrito -> relido.",
    ])


# ============================================================================
# Orchestration
# ============================================================================

@dataclass
class MigrationResult:
    exit_code: int
    report: str


@dataclass
class PersonPlan:
    pessoas_note: BuiltNote | None
    person_notes: dict[str, BuiltNote]
    person_paths: dict[str, str]
    orphan_ids: list[str]
    has_pessoas_anchor: bool


def _person_first_seen(records: list[tuple[dict, Path]]) -> dict[str, datetime]:
    first_seen: dict[str, datetime] = {}
    for record, _ in records:
        started = parse_old_date(record["startedAt"])
        for pid in record.get("personIDs") or []:
            key = uid(pid)
            if key not in first_seen or started < first_seen[key]:
                first_seen[key] = started
    return first_seen


def _build_person_plan(
    records: list[tuple[dict, Path]], people: list[dict], anchor_dt: datetime, taken_root_slugs: set[str],
) -> PersonPlan:
    people_by_id = {uid(p["id"]): p for p in people}
    person_first_seen = _person_first_seen(records)
    referenced = {uid(pid) for record, _ in records for pid in (record.get("personIDs") or [])}
    orphan_ids = sorted(referenced - set(people_by_id))
    has_pessoas_anchor = bool(people or orphan_ids)

    pessoas_note = None
    pessoas_slug = None
    if has_pessoas_anchor:
        pessoas_note = build_anchor_note("Pessoas", anchor_dt)
        pessoas_note.slug = unique_slug("pessoas", taken_root_slugs)
        pessoas_slug = pessoas_note.slug

    person_notes: dict[str, BuiltNote] = {}
    person_paths: dict[str, str] = {}
    taken_people_slugs: set[str] = set()

    def place(note: BuiltNote, key: str) -> None:
        note.slug = unique_slug(note.slug, taken_people_slugs)
        note.parent = pessoas_slug
        person_notes[key] = note
        person_paths[key] = f"/{pessoas_slug}/{note.slug}.md"

    for person in people:
        pid = uid(person["id"])
        place(build_person_note(person, person_first_seen.get(pid, anchor_dt)), pid)
    for pid in orphan_ids:
        place(build_orphan_stub(pid, person_first_seen.get(pid, anchor_dt)), pid)

    return PersonPlan(pessoas_note, person_notes, person_paths, orphan_ids, has_pessoas_anchor)


def _build_project_notes(projects: list[dict], taken_root_slugs: set[str]) -> dict[str, BuiltNote]:
    project_notes: dict[str, BuiltNote] = {}
    for project in projects:
        note = build_project_note(project)
        note.slug = unique_slug(slugify(project["name"]), taken_root_slugs)
        project_notes[uid(project["id"])] = note
    return project_notes


def _build_all_session_notes(
    records: list[tuple[dict, Path]], *, project_notes: dict[str, BuiltNote], inbox_slug: str,
    person_paths: dict[str, str], legacy_audio_root: Path,
) -> list[BuiltNote]:
    taken_slugs_by_parent: dict[str, set[str]] = {}
    session_notes: list[BuiltNote] = []
    for record, session_dir in records:
        links = sorted({
            person_paths[uid(pid)] for pid in (record.get("personIDs") or []) if uid(pid) in person_paths
        })
        note = build_session_note(
            record, session_dir=session_dir, legacy_audio_root=legacy_audio_root, links=links,
        )
        project_id = record.get("projectID")
        project = project_notes.get(uid(project_id)) if project_id else None
        parent_slug = project.slug if project else inbox_slug
        bucket = taken_slugs_by_parent.setdefault(parent_slug, set())
        base_slug = slugify(note.title) or parse_old_date(record["startedAt"]).strftime("%Y-%m-%d-%H%M")
        note.slug = unique_slug(base_slug, bucket)
        note.parent = parent_slug
        session_notes.append(note)
    return session_notes


def _write_staging(staging: Path, all_notes: list[BuiltNote], session_count: int, anchor_date: date) -> None:
    write_all(staging, all_notes)
    write_indexes(staging, all_notes)
    write_log(staging, session_count, anchor_date)
    (staging / "AGENTS.md").write_text(CORPUS_AGENTS_MD, encoding="utf-8")


@dataclass
class VerifyResult:
    ok: bool
    reread_mismatches: list[str]
    count_mismatches: list[str]


def _verify(
    staging: Path, all_notes: list[BuiltNote], records: list[tuple[dict, Path]],
    projects: list[dict], people: list[dict], orphan_ids: list[str], has_pessoas_anchor: bool,
) -> VerifyResult:
    loaded_counts = count_from_records(records, projects, people, set(orphan_ids), has_pessoas_anchor)
    written_counts = count_from_built(all_notes)
    reread_mismatches = reread_check(staging, all_notes)
    reread_counts = count_from_reread(staging)
    count_mismatches = compare_counts(loaded_counts, written_counts, reread_counts)
    return VerifyResult(not reread_mismatches and not count_mismatches, reread_mismatches, count_mismatches)


def _finalize_dest(
    staging: Path, dest: Path, source: Path, records: list[tuple[dict, Path]], args: argparse.Namespace,
) -> list[str]:
    if dest.exists():
        shutil.rmtree(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(staging), str(dest))
    if args.keep_diagnostics:
        dump_diagnostics(dest.parent / f"{dest.name}-diagnostics", records)
    removed = purge_semantic_index(source)
    return [f"Semantic index purged: {', '.join(removed)}"] if removed else []


def _report_lines(
    all_notes: list[BuiltNote], session_notes: list[BuiltNote], projects: list[dict], people: list[dict],
    person_notes: dict[str, BuiltNote], verify: VerifyResult,
) -> list[str]:
    orphan_count = sum(1 for n in person_notes.values() if n.frontmatter.get("x_cueme_orphan"))
    lines = [render_report_table(all_notes, session_notes, projects, people, orphan_count)]
    if verify.reread_mismatches:
        lines.append("Re-read mismatches:")
        lines.extend(f"  - {m}" for m in verify.reread_mismatches)
    if verify.count_mismatches:
        lines.append("Count reconciliation mismatches:")
        lines.extend(f"  - {m}" for m in verify.count_mismatches)
    return lines


def _load_records(source: Path) -> list[tuple[dict, Path]]:
    records: list[tuple[dict, Path]] = []
    for session_dir in discover_session_dirs(source):
        raw = read_session_json(session_dir / "session.json")
        records.append((merge_canonical_fields(raw, session_dir / "note.md"), session_dir))
    return records


def run_migration(args: argparse.Namespace) -> MigrationResult:
    source = Path(args.source).resolve()
    legacy_audio_root = Path(args.legacy_audio).resolve()
    dest = Path(args.dest).resolve()

    if dest.exists() and any(dest.iterdir()) and not args.force:
        return MigrationResult(2, f"REFUSED: --dest {dest} is not empty; pass --force to overwrite it.\n")

    records = _load_records(source)
    projects, people = load_entities(Path(args.entities).resolve())

    anchor_date = today_local()
    anchor_dt = datetime(anchor_date.year, anchor_date.month, anchor_date.day, tzinfo=timezone.utc)

    taken_root_slugs: set[str] = set()
    inbox_note = build_anchor_note("Inbox", anchor_dt)
    inbox_note.slug = unique_slug("inbox", taken_root_slugs)

    person_plan = _build_person_plan(records, people, anchor_dt, taken_root_slugs)
    project_notes = _build_project_notes(projects, taken_root_slugs)
    session_notes = _build_all_session_notes(
        records, project_notes=project_notes, inbox_slug=inbox_note.slug,
        person_paths=person_plan.person_paths, legacy_audio_root=legacy_audio_root,
    )

    all_notes: list[BuiltNote] = [inbox_note, *project_notes.values()]
    if person_plan.pessoas_note:
        all_notes.append(person_plan.pessoas_note)
    all_notes += session_notes
    all_notes += list(person_plan.person_notes.values())

    staging = Path(tempfile.mkdtemp(prefix="okf-migrate-"))
    try:
        _write_staging(staging, all_notes, len(session_notes), anchor_date)
        verify = _verify(
            staging, all_notes, records, projects, people,
            person_plan.orphan_ids, person_plan.has_pessoas_anchor,
        )
        report_lines = _report_lines(
            all_notes, session_notes, projects, people, person_plan.person_notes, verify,
        )
        if verify.ok and not args.dry_run:
            report_lines.extend(_finalize_dest(staging, dest, source, records, args))
    finally:
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)

    total = len(verify.reread_mismatches) + len(verify.count_mismatches)
    report_lines.append("RESULT: OK — 0 mismatches" if verify.ok else f"RESULT: FAILED — {total} mismatches")
    return MigrationResult(0 if verify.ok else 3, "\n".join(report_lines) + "\n")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="migrate-okf.py", description="One-shot migration to the OKF v0.2 corpus.",
    )
    parser.add_argument("--source", required=True, help="Old Session Archive root")
    parser.add_argument("--entities", required=True, help="knowledge-entities.json path")
    parser.add_argument("--legacy-audio", required=True, help="Legacy recordings/ directory")
    parser.add_argument("--dest", required=True, help="New OKF corpus root (must be empty or absent)")
    parser.add_argument("--dry-run", action="store_true", help="Run both verify checks, write nothing")
    parser.add_argument("--force", action="store_true", help="Overwrite a non-empty --dest")
    parser.add_argument(
        "--keep-diagnostics", action="store_true",
        help="Dump raw diagnostics.events outside the bundle instead of discarding them",
    )
    parser.add_argument("--verbose", action="store_true", help="Print extra detail (reserved)")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    source = Path(args.source)
    before_hash = hash_tree(source)
    result = run_migration(args)
    after_hash = hash_tree(source)
    print(result.report, end="")
    if before_hash != after_hash:
        print("FATAL: --source was modified during migration. This must never happen.")
        return 4
    return result.exit_code


if __name__ == "__main__":
    raise SystemExit(main())

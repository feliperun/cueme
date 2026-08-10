#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6.0", "pytest>=8.0"]
# ///
"""Tests for scripts/migrate-okf.py — the one-shot OKF corpus migration.

Every test builds its own synthetic "old format" tree (session.json + note.md
archive, knowledge-entities.json catalogue, legacy audio directory). The
migration script is NEVER pointed at a real user archive here — see
constitution.md §8 and AGENTS.md.

Run with:
    uv run scripts/tests/test_migrate_okf.py
    uv run pytest scripts/tests            (if pytest/pyyaml already available)
"""
from __future__ import annotations

import importlib.util
import json
import sys
from datetime import date
from pathlib import Path

import pytest
import yaml

SCRIPT_PATH = Path(__file__).resolve().parents[1] / "migrate-okf.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("migrate_okf", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    # dataclasses (3.12+) resolves annotations via sys.modules[cls.__module__];
    # the module must be registered before exec_module runs.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


migrate_okf = _load_module()


# ---------------------------------------------------------------------------
# Fixture builders — synthetic "old format" archive
# ---------------------------------------------------------------------------

def default_session_json(**overrides) -> dict:
    """Builds a dict matching exactly what MemoryNote/SessionRecord's
    JSONEncoder(dateEncodingStrategy: .iso8601, sortedKeys) produced in
    production, including the flat-array encoding Swift uses for
    Dictionary<NonStringKey, Value> (verified against the real Swift
    compiler: [Speaker: String] and [UUID: CoachFeedback] serialize as
    alternating [key, value, key, value, ...] arrays, NOT JSON objects).
    """
    data = {
        "id": "10000000-0000-4000-8000-000000000001",
        "schemaVersion": 4,
        "startedAt": "2026-08-08T14:30:11Z",
        "endedAt": "2026-08-08T15:00:11Z",
        "mode": "meeting",
        "training": False,
        "conversationLang": "pt-BR",
        "nativeLang": "pt-BR",
        "goal": "Definir a estratégia de mobilidade da diretoria",
        "transcript": [],
        "coachCards": [],
        "summaryBullets": [],
        "minutes": {"overview": "", "topics": []},
        "participantNames": ["self", "Felipe", "other", "Marina"],
        "vocabulary": {"keyterms": [], "replacements": {}},
        "hasAudio": False,
        "audioDuration": 0,
        "diagnostics": {"events": [], "aggregates": {}, "kindCounts": []},
        "coachFeedback": [],
        "archiveFolderName": "2026-08-08_14-30-11_10000000",
        "notes": [],
        "takeaways": [],
        "origin": "live",
        "review": {"decisions": [], "openQuestions": [], "followUp": ""},
        "artifacts": [],
        "personIDs": [],
        "noteKind": "meeting",
        "markdownBody": "",
        "labels": [],
        "attachments": [],
        "titleSource": "fallback",
        "modifiedAt": "2026-08-08T15:00:11Z",
    }
    data.update(overrides)
    return data


def write_old_note_md(
    path: Path,
    *,
    id_: str,
    title: str,
    kind: str = "meeting",
    created_at: str = "2026-08-08T14:30:11Z",
    updated_at: str = "2026-08-08T15:12:44Z",
    project_id: str | None = None,
    labels: list[str] | None = None,
    title_source: str = "user",
    has_recording: bool = False,
    body: str = "",
) -> None:
    """Mirrors NoteDocument.frontmatter(for:) + userBodyLines(for:) exactly
    (git history, CueMe/Model/NoteDocument.swift:11-33), the format the old
    app actually wrote to note.md.
    """
    labels = labels or []
    lines = [
        "---",
        f'id: "{id_}"',
        f'title: "{title}"',
        f"kind: {kind}",
        f'created_at: "{created_at}"',
        f'updated_at: "{updated_at}"',
        f"project_id: {json.dumps(project_id) if project_id else 'null'}",
        f"labels: {json.dumps(labels)}",
        f"title_source: {title_source}",
        f"has_recording: {'true' if has_recording else 'false'}",
        "---",
        "",
        "<!-- cueme:body:start -->",
    ]
    if body:
        lines.extend(body.split("\n"))
    lines.append("<!-- cueme:body:end -->")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_session_dir(
    root: Path,
    relative: str,
    *,
    session_overrides: dict | None = None,
    note_md_kwargs: dict | None = None,
    write_note_md: bool = True,
) -> Path:
    """Creates <root>/<relative>/{session.json, note.md} matching the real
    SessionStore.save() layout.
    """
    directory = root / relative
    directory.mkdir(parents=True, exist_ok=True)
    session = default_session_json(**(session_overrides or {}))
    (directory / "session.json").write_text(json.dumps(session, indent=2), encoding="utf-8")
    if write_note_md:
        kwargs = {
            "id_": session["id"],
            "title": session.get("displayTitle") or "Sessão",
        }
        kwargs.update(note_md_kwargs or {})
        write_old_note_md(directory / "note.md", **kwargs)
    return directory


def write_entities_json(path: Path, *, projects: list[dict] | None = None, people: list[dict] | None = None) -> None:
    path.write_text(
        json.dumps({"projects": projects or [], "people": people or []}, indent=2),
        encoding="utf-8",
    )


def run_cli(argv: list[str]) -> tuple[int, str]:
    """Runs migrate_okf.main() capturing stdout via a StringIO-backed print
    redirect, returning (exit_code, output)."""
    import contextlib
    import io

    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        code = migrate_okf.main(argv)
    return code, buffer.getvalue()


# ---------------------------------------------------------------------------
# Unit tests — highest-risk pure logic
# ---------------------------------------------------------------------------

def test_slugify_folds_diacritics_and_limits_length():
    assert migrate_okf.slugify("Estratégia de frota elétrica") == "estrategia-de-frota-eletrica"
    assert migrate_okf.slugify("Ação!! & Reação??") == "acao-reacao"
    long_title = "x" * 100
    assert len(migrate_okf.slugify(long_title)) <= 54


def test_unique_slug_avoids_collision_and_reserved_names():
    taken: set[str] = set()
    first = migrate_okf.unique_slug("acme", taken)
    second = migrate_okf.unique_slug("acme", taken)
    assert first == "acme"
    assert second == "acme-2"
    reserved = migrate_okf.unique_slug("index", taken)
    assert reserved not in {"index", "log", "agents"}


def test_escape_and_unescape_line_round_trip():
    line = "<!-- cueme:not-really-a-marker -->"
    escaped = migrate_okf.escape_line(line)
    assert escaped == "\\" + line
    assert migrate_okf.unescape_line(escaped) == line
    # a line with no marker-like prefix is untouched
    plain = "Just a normal line."
    assert migrate_okf.escape_line(plain) == plain
    assert migrate_okf.unescape_line(plain) == plain
    # escaping twice then unescaping once must still look escaped once (invertible, not idempotent)
    twice = migrate_okf.escape_line(escaped)
    assert twice == "\\\\" + line
    assert migrate_okf.unescape_line(twice) == escaped


def test_quantize3_shortest_round_trip_form():
    assert migrate_okf.quantize3(42.0) == 42.0
    assert migrate_okf.format_double(migrate_okf.quantize3(42.0)) == "42.0"
    assert migrate_okf.format_double(migrate_okf.quantize3(0.9436)) == "0.944"
    assert migrate_okf.format_double(migrate_okf.quantize3(1785.4)) == "1785.4"


def test_format_new_date_is_utc_with_millisecond_fraction():
    dt = migrate_okf.parse_old_date("2026-08-08T14:30:11Z")
    assert migrate_okf.format_new_date(dt) == "2026-08-08T14:30:11.000Z"


def test_merge_canonical_fields_note_md_labels_and_body_always_win_even_when_empty(tmp_path):
    """The single most dangerous edge case in mergeCanonicalFields: labels and
    markdownBody are unconditionally overwritten from note.md — even when
    note.md declares them empty — silently discarding JSON's values. The
    migration must replicate this exactly (constitution.md §risk).
    """
    note_md = tmp_path / "note.md"
    write_old_note_md(
        note_md,
        id_="10000000-0000-4000-8000-000000000001",
        title="Título vindo do note.md",
        labels=[],
        body="",
    )
    record = default_session_json(
        labels=["json-label-should-be-wiped"],
        markdownBody="JSON body should be wiped too",
    )
    merged = migrate_okf.merge_canonical_fields(record, note_md)
    assert merged["labels"] == []
    assert merged["markdownBody"] == ""
    assert merged["displayTitle"] == "Título vindo do note.md"


# ---------------------------------------------------------------------------
# AC1 — dry-run writes nothing but still runs both verify checks
# ---------------------------------------------------------------------------

def test_ac1_dry_run_writes_nothing_and_still_runs_both_checks(tmp_path):
    source = tmp_path / "Session Archive"
    write_session_dir(source, "_Inbox/session-1")
    entities = tmp_path / "knowledge-entities.json"
    write_entities_json(entities)
    legacy_audio = tmp_path / "recordings"
    legacy_audio.mkdir()
    dest = tmp_path / "Corpus"

    code, out = run_cli([
        "--source", str(source),
        "--entities", str(entities),
        "--legacy-audio", str(legacy_audio),
        "--dest", str(dest),
        "--dry-run",
    ])

    assert code == 0
    assert not dest.exists()
    assert "RESULT: OK" in out
    # both checks ran and reported
    assert "re-read" in out.lower() or "reread" in out.lower()
    assert "contagem" in out.lower() or "reconcil" in out.lower()


# ---------------------------------------------------------------------------
# AC2 — an externally-edited note.md wins over the JSON
# ---------------------------------------------------------------------------

def test_ac2_external_note_md_edit_survives_migration(tmp_path):
    source = tmp_path / "Session Archive"
    directory = write_session_dir(
        source,
        "_Inbox/session-1",
        session_overrides={
            "displayTitle": "Título antigo do JSON",
            "titleSource": "generated",
            "labels": ["json-only-label"],
            "markdownBody": "Corpo antigo do JSON.",
        },
        note_md_kwargs={
            "id_": "10000000-0000-4000-8000-000000000001",
            "title": "Título editado por fora no Finder",
            "labels": ["editado-por-fora"],
            "title_source": "user",
            "body": "Corpo editado manualmente pelo usuário.",
        },
    )
    entities = tmp_path / "knowledge-entities.json"
    write_entities_json(entities)
    legacy_audio = tmp_path / "recordings"
    legacy_audio.mkdir()
    dest = tmp_path / "Corpus"

    code, out = run_cli([
        "--source", str(source),
        "--entities", str(entities),
        "--legacy-audio", str(legacy_audio),
        "--dest", str(dest),
    ])
    assert code == 0, out

    written = next(dest.rglob("titulo-editado-por-fora-no-finder.md"), None)
    assert written is not None, list(dest.rglob("*.md"))
    text = written.read_text(encoding="utf-8")
    frontmatter, body = migrate_okf.split_frontmatter(text)
    assert frontmatter["title"] == "Título editado por fora no Finder"
    assert frontmatter["tags"] == ["editado-por-fora"]
    assert "Corpo editado manualmente pelo usuário." in body
    assert "Corpo antigo do JSON." not in text
    assert "json-only-label" not in text


# ---------------------------------------------------------------------------
# AC3 — any divergent count exits non-zero
# ---------------------------------------------------------------------------

def test_ac3_count_mismatch_causes_nonzero_exit(tmp_path, monkeypatch):
    source = tmp_path / "Session Archive"
    write_session_dir(source, "_Inbox/session-1")
    entities = tmp_path / "knowledge-entities.json"
    write_entities_json(entities)
    legacy_audio = tmp_path / "recordings"
    legacy_audio.mkdir()
    dest = tmp_path / "Corpus"

    # Force a lie in the re-read counting phase to prove a real divergence
    # is caught and propagated to a non-zero exit, not swallowed.
    real_count_from_reread = migrate_okf.count_from_reread

    def lying_count_from_reread(staging_root):
        counts = dict(real_count_from_reread(staging_root))
        counts["notas"] = counts.get("notas", 0) + 999
        return counts

    monkeypatch.setattr(migrate_okf, "count_from_reread", lying_count_from_reread)

    code, out = run_cli([
        "--source", str(source),
        "--entities", str(entities),
        "--legacy-audio", str(legacy_audio),
        "--dest", str(dest),
    ])

    assert code != 0
    assert "RESULT: OK" not in out
    assert "mismatch" in out.lower()


# ---------------------------------------------------------------------------
# AC4 — re-running with --force against the same --dest is idempotent
# ---------------------------------------------------------------------------

def test_ac4_rerun_with_force_is_idempotent(tmp_path, monkeypatch):
    monkeypatch.setattr(migrate_okf, "today_local", lambda: date(2026, 8, 9))

    source = tmp_path / "Session Archive"
    write_session_dir(
        source,
        "_Inbox/session-1",
        session_overrides={"displayTitle": "Sessão idempotente"},
        note_md_kwargs={"title": "Sessão idempotente"},
    )
    entities = tmp_path / "knowledge-entities.json"
    write_entities_json(entities)
    legacy_audio = tmp_path / "recordings"
    legacy_audio.mkdir()
    dest = tmp_path / "Corpus"

    argv = [
        "--source", str(source),
        "--entities", str(entities),
        "--legacy-audio", str(legacy_audio),
        "--dest", str(dest),
    ]
    code1, _ = run_cli(argv)
    assert code1 == 0
    hash1 = migrate_okf.hash_tree(dest)

    code2, _ = run_cli(argv + ["--force"])
    assert code2 == 0
    hash2 = migrate_okf.hash_tree(dest)

    assert hash1 == hash2


# ---------------------------------------------------------------------------
# AC5 — a session that belonged to a project nests under that project's note
# ---------------------------------------------------------------------------

def test_ac5_session_with_project_becomes_child_of_project_note(tmp_path):
    project_id = "20000000-0000-4000-8000-000000000001"
    source = tmp_path / "Session Archive"
    write_session_dir(
        source,
        "acme-20000000/session-1",
        session_overrides={
            "projectID": project_id,
            "displayTitle": "Reunião com a Acme",
        },
        note_md_kwargs={"title": "Reunião com a Acme", "project_id": project_id},
    )
    entities = tmp_path / "knowledge-entities.json"
    write_entities_json(
        entities,
        projects=[{
            "id": project_id,
            "name": "Acme",
            "summary": "Contexto e histórico da conta Acme.",
            "createdAt": "2026-01-01T00:00:00Z",
            "archived": False,
        }],
    )
    legacy_audio = tmp_path / "recordings"
    legacy_audio.mkdir()
    dest = tmp_path / "Corpus"

    code, out = run_cli([
        "--source", str(source),
        "--entities", str(entities),
        "--legacy-audio", str(legacy_audio),
        "--dest", str(dest),
    ])
    assert code == 0, out

    assert (dest / "acme.md").exists()
    child = dest / "acme" / "reuniao-com-a-acme.md"
    assert child.exists(), list(dest.rglob("*.md"))


# ---------------------------------------------------------------------------
# AC6 — a personID missing from the catalogue becomes a linked orphan stub
# ---------------------------------------------------------------------------

def test_ac6_missing_person_creates_orphan_stub_and_links(tmp_path):
    missing_person_id = "30000000-0000-4000-8000-0000000000ff"
    source = tmp_path / "Session Archive"
    write_session_dir(
        source,
        "_Inbox/session-1",
        session_overrides={
            "personIDs": [missing_person_id],
            "displayTitle": "Sessão com pessoa órfã",
        },
        note_md_kwargs={"title": "Sessão com pessoa órfã"},
    )
    entities = tmp_path / "knowledge-entities.json"
    write_entities_json(entities, people=[])
    legacy_audio = tmp_path / "recordings"
    legacy_audio.mkdir()
    dest = tmp_path / "Corpus"

    code, out = run_cli([
        "--source", str(source),
        "--entities", str(entities),
        "--legacy-audio", str(legacy_audio),
        "--dest", str(dest),
    ])
    assert code == 0, out

    stub = dest / "pessoas" / f"pessoa-{missing_person_id[:8]}.md"
    assert stub.exists(), list((dest / "pessoas").rglob("*.md"))
    stub_fm, _ = migrate_okf.split_frontmatter(stub.read_text(encoding="utf-8"))
    assert stub_fm.get("x_cueme_orphan") is True

    note_path = dest / "inbox" / "sessao-com-pessoa-orfa.md"
    assert note_path.exists()
    note_fm, _ = migrate_okf.split_frontmatter(note_path.read_text(encoding="utf-8"))
    assert f"/pessoas/pessoa-{missing_person_id[:8]}.md" in note_fm.get("x_cueme_links", [])


# ---------------------------------------------------------------------------
# AC7 — refuses a non-empty --dest without --force, before writing anything
# ---------------------------------------------------------------------------

def test_ac7_refuses_nonempty_dest_without_force(tmp_path):
    source = tmp_path / "Session Archive"
    write_session_dir(source, "_Inbox/session-1")
    entities = tmp_path / "knowledge-entities.json"
    write_entities_json(entities)
    legacy_audio = tmp_path / "recordings"
    legacy_audio.mkdir()
    dest = tmp_path / "Corpus"
    dest.mkdir()
    (dest / "pre-existing.txt").write_text("do not touch", encoding="utf-8")

    code, out = run_cli([
        "--source", str(source),
        "--entities", str(entities),
        "--legacy-audio", str(legacy_audio),
        "--dest", str(dest),
    ])

    assert code != 0
    assert (dest / "pre-existing.txt").read_text(encoding="utf-8") == "do not touch"
    assert list(dest.iterdir()) == [dest / "pre-existing.txt"]


# ---------------------------------------------------------------------------
# AC8 — not one byte of --source changes
# ---------------------------------------------------------------------------

def test_ac8_source_bytes_untouched(tmp_path):
    source = tmp_path / "Session Archive"
    write_session_dir(
        source,
        "_Inbox/session-1",
        session_overrides={"hasAudio": True, "audioDuration": 12.5},
    )
    (source / "_Inbox" / "session-1" / "self.m4a").write_bytes(b"fake-audio-bytes")
    entities = tmp_path / "knowledge-entities.json"
    write_entities_json(entities)
    legacy_audio = tmp_path / "recordings"
    legacy_audio.mkdir()
    dest = tmp_path / "Corpus"

    before = migrate_okf.hash_tree(source)
    code, _ = run_cli([
        "--source", str(source),
        "--entities", str(entities),
        "--legacy-audio", str(legacy_audio),
        "--dest", str(dest),
    ])
    after = migrate_okf.hash_tree(source)

    assert code == 0
    assert before == after


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))

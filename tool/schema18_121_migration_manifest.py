"""Independent literal oracle for a fixture produced by frozen 1.20 Dart code.

This checker never uses the application serializer and never modifies SQLite.
Usage: python tool/schema18_121_migration_manifest.py FIXTURE FROZEN_SOURCE
"""
import datetime as dt
import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import sys

SOURCE = "410da05d341d8ea88915fe8a197d3df6eee54283"


def encoded(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def digest(value):
    return hashlib.sha256(value).hexdigest()


def epoch(minute):
    return int(dt.datetime(2026, 10, 6, 12, minute, tzinfo=dt.timezone.utc).timestamp() * 1000)


def main():
    fixture, source = map(Path, sys.argv[1:])
    actual_source = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if actual_source != SOURCE:
        raise RuntimeError("Wrong frozen source commit")
    report_sources = [
        {"id": "report", "title": "Informe QA", "text": "Sesión QA: 3 series. Comida QA: 450 kcal. Peso QA: 72,5 kg."},
        {"id": "prior_report", "title": "Periodo previo QA", "text": "Registro previo QA incompleto. No permite concluir una tendencia."},
    ]
    guide_sources = [{"id": "exercise_guide:dominadas", "title": "Guía QA", "text": "Dominadas con carga y agarre prona. Escápulas activas."}]
    guide_context = {"exercise": "Dominadas", "cues": ["Escápulas activas"], "progressionNote": "Mantén la variante elegida.", "anchor": None, "grip": "prona", "loaded": True}
    expected = {
        "profiles": [{"id": 1, "start_date": "2026-09-28", "height_cm": 175.0, "protein_min": 160, "protein_max": 170, "kcal_target": 2100}],
        "exercises": [{"id": 901, "name": "Dominadas QA", "form_cues": "Escápulas activas", "tracks_load": 1}],
        "sessions": [{"id": 902, "date": "2026-10-05", "type": "bloques", "total_sec": 1500, "warmup_sec": 360, "cooldown_sec": 180, "rest_sec": 300, "rounds_done": 3, "rpe": 7, "context": "QA sintética: fuente18", "notes": "No representa datos de una persona", "technique_ok": 1, "full_range": 1, "recovery_ok": 1}],
        "session_sets": [{"id": 903, "session_id": 902, "exercise_id": 901, "set_index": 1, "reps": 8, "load_kg": 4.5, "rir": 2}],
        "meals": [{"id": 904, "date": "2026-10-05", "time": "08:10", "slot": "desayuno", "notes": "Comida QA sintética"}],
        "meal_items": [{"id": 905, "meal_id": 904, "label": "Plato QA", "quantity": 1.0, "quantity_unit": "porción", "kcal": 450.0, "protein": 30.0, "carbs": 45.0, "fat": 15.0, "source_verified": 0}],
        "body_weights": [{"id": 906, "date": "2026-10-05", "kg": 72.5, "fasted": 1, "moment": "ayunas", "time": "06:50"}],
    }
    expected["ai_conversations"] = []
    for ident, kind, title, sources, context, minute in [
        (1, "reportQuestion", "QA · informe sintético", report_sources, None, 0),
        (2, "exerciseQuestion", "QA · guía Dominadas", guide_sources, guide_context, 2),
    ]:
        source_json = encoded(sources)
        guide_json = None if context is None else encoded(context)
        expected["ai_conversations"].append({
            "id": ident, "kind": kind, "title": title,
            "range_start": "2026-09-28" if ident == 1 else None,
            "range_end": "2026-10-05" if ident == 1 else None,
            "model": "gpt-6-luna", "contract_version": 2,
            "sources_json": source_json, "sources_hash": digest(source_json.encode("utf-8")),
            "guide_context_json": guide_json, "guide_context_hash": None if guide_json is None else digest(guide_json.encode("utf-8")),
            "created_at": epoch(minute),
        })
    expected["ai_messages"] = []
    for ident, conversation, role, message, citations, minute in [
        (1, 1, "user", "¿Qué está registrado?", [], 0),
        (2, 1, "assistant", "La fuente registra sesión, comida y peso; el periodo previo está incompleto.", [{"source_id": "report", "quote": "Sesión QA: 3 series."}, {"source_id": "prior_report", "quote": "Registro previo QA incompleto."}], 0),
        (3, 1, "user", "¿Hay evidencia de tendencia?", [], 1),
        (4, 1, "assistant", "La fuente previa no permite concluir una tendencia.", [{"source_id": "prior_report", "quote": "No permite concluir una tendencia."}], 1),
        (5, 2, "user", "¿Qué variante corresponde?", [], 2),
        (6, 2, "assistant", "La guía corresponde a dominadas con carga y agarre prona.", [{"source_id": "exercise_guide:dominadas", "quote": "Dominadas con carga y agarre prona."}], 2),
    ]:
        expected["ai_messages"].append({"id": ident, "conversation_id": conversation, "role": role, "message_text": message, "citations_json": encoded(citations), "model": "gpt-6-luna", "contract_version": 2, "created_at": epoch(minute)})
    with sqlite3.connect(f"file:{fixture.as_posix()}?mode=ro", uri=True) as database:
        database.row_factory = sqlite3.Row
        assert database.execute("PRAGMA user_version").fetchone()[0] == 18
        assert database.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        assert database.execute("PRAGMA foreign_key_check").fetchall() == []
        reminder_setting = {"kind": "sesion", "enabled": 0, "hour": 14, "minute": 15, "threshold": None}
        assert dict(database.execute("SELECT * FROM reminders WHERE kind='sesion'").fetchone()) == reminder_setting
        assert database.execute("SELECT COUNT(*) FROM reminders").fetchone()[0] == 11
        for table, rows in expected.items():
            actual = [dict(row) for row in database.execute(f'SELECT * FROM "{table}" ORDER BY id')]
            assert len(actual) == len(rows), (table, "count", len(actual), len(rows))
            for stored, wanted in zip(actual, rows):
                for key, value in wanted.items():
                    assert stored[key] == value, (table, wanted["id"], key, stored[key], value)
        inventory = [row[0] for row in database.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")]
    files = ["lib/data/database.dart", "lib/data/tables.dart", "lib/data/repositories/ai_conversation_repository.dart", "lib/domain/ai_context.dart", "pubspec.lock"]
    manifest = {"format": "seguimiento-schema18-independent-oracle-v1", "synthetic_only": True, "schema_version": 18, "source_commit": SOURCE, "fixture_sha256": digest(fixture.read_bytes()), "source_sha256": {name: digest((source / name).read_bytes()) for name in files}, "table_inventory": inventory, "reminder_setting": reminder_setting, "expected": expected}
    target = fixture.with_name("schema18-synthetic-manifest.json")
    target.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Verified literal oracle: {len(inventory)} tables, 2 conversations, 6 messages; SHA256 {manifest['fixture_sha256']}")


if __name__ == "__main__":
    main()

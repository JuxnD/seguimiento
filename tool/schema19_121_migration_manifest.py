"""Read-only, independent literal oracle for genuine unpublished schema19."""
import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import sys

SOURCE = "afaaf86e1718d49acaa86e13a08515c7ea699421"


def main():
    fixture, source = map(Path, sys.argv[1:])
    assert subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip() == SOURCE
    expected = {
        "sessions": [
            {"id": 902, "date": "2026-10-19", "start_time": "07:20", "type": "bloques", "total_sec": 1500, "warmup_sec": 360, "cooldown_sec": 180, "rest_sec": 300, "rpe": 7, "context": "QA schema19: core", "notes": "Preservar todos los campos", "technique_ok": 1, "full_range": 1, "recovery_ok": 1, "imported": 0},
            {"id": 903, "date": "2026-10-12", "type": "otro", "total_sec": 3600, "warmup_sec": 0, "cooldown_sec": 0, "rest_sec": 0, "mode": "test", "context": "Test 1 · torso, core y habilidades", "imported": 0},
            {"id": 906, "date": "2026-09-11", "type": "resistencia", "total_sec": 960, "rounds_done": 7, "mode": "cindy", "context": "QA importado", "imported": 1},
        ],
        "session_sets": [{"id": 903, "session_id": 902, "exercise_id": 901, "set_index": 1, "reps": 12, "rir": 2}],
        "fitness_tests": [
            {"id": 1, "date": "2026-10-12", "round": 1, "item": "pullup", "side": None, "value": 8.0, "clean": 1},
            {"id": 2, "date": "2026-10-12", "round": 1, "item": "wall_handstand", "side": None, "value": 35.0, "clean": 0},
            {"id": 3, "date": "2026-10-12", "round": 1, "item": "one_arm_pushup", "side": "I", "value": 3.0, "clean": 1},
        ],
        "ladder_states": [
            {"ladder": "dragon_flag", "step": 2, "since": "2026-10-12", "lumbar_on": "2026-10-19"},
            {"ladder": "v_up", "step": 3, "since": "2026-10-15", "lumbar_on": None},
        ],
        "football_games": [{"id": 907, "date": "2026-09-13", "minutes": 0, "notes": "QA por confirmar", "imported": 1}],
    }
    with sqlite3.connect(f"file:{fixture.as_posix()}?mode=ro", uri=True) as db:
        db.row_factory = sqlite3.Row
        assert db.execute("PRAGMA user_version").fetchone()[0] == 19
        assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        assert db.execute("PRAGMA foreign_key_check").fetchall() == []
        for table, rows in expected.items():
            order = "ladder" if table == "ladder_states" else "id"
            actual = [dict(row) for row in db.execute(f'SELECT * FROM "{table}" ORDER BY {order}')]
            assert len(actual) == len(rows), (table, "count")
            for stored, wanted in zip(actual, rows):
                for key, value in wanted.items():
                    assert stored[key] == value, (table, key, stored[key], value)
        inventory = [row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")]
    digest = lambda data: hashlib.sha256(data).hexdigest()
    files = ["lib/data/database.dart", "lib/data/tables.dart", "lib/data/repositories/fitness_test_repository.dart", "lib/data/repositories/ladder_repository.dart", "pubspec.lock"]
    manifest = {"format": "seguimiento-schema19-independent-oracle-v1", "synthetic_only": True, "schema_version": 19, "source_commit": SOURCE, "fixture_sha256": digest(fixture.read_bytes()), "source_sha256": {name: digest((source / name).read_bytes()) for name in files}, "table_inventory": inventory, "expected": expected, "sole_allowed_change": {"table": "sessions", "id": 903, "column": "total_sec", "before": 3600, "after": 0}}
    fixture.with_name("schema19-synthetic-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Verified schema19 oracle: {len(inventory)} tables; {manifest['fixture_sha256']}")


if __name__ == "__main__":
    main()

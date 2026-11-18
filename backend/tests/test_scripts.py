"""scripts/status.py and scripts/export.py against a small study."""

import csv

from app import models
from scripts.export import export
from scripts.status import build_report

from .conftest import load
from .test_participants import register


def upload(client, user_id, variant="A", session_id=None, kind="clean"):
    body = load(kind)
    body["user_id"] = user_id
    body["variant"] = variant
    if session_id:
        body["session_id"] = session_id
    assert client.post("/api/sessions", json=body).status_code == 200


def rows(path):
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def small_study(client):
    register(client, user_id="Tiger42x")
    register(client, user_id="Panda77y", email="p@example.com")
    register(client, user_id="Quiet01z", email="q@example.com")
    upload(client, "Tiger42x", "A")
    upload(client, "Tiger42x", "A", session_id="2", kind="gaps")
    upload(client, "Panda77y", "A")
    upload(client, "Panda77y", "B", session_id="2")  # switched version
    upload(client, "TIGER42X", "A")                  # typo'd ID in the app
    upload(client, "Tiger42x", "C", session_id="3")  # internal test


def test_status_flags_what_needs_attention(client, db):
    small_study(client)
    with db() as s:
        report = build_report(s)
    assert "Registered participants: 3" in report
    assert "Variant C test sessions, ignored below: 1" in report
    assert "'TIGER42X'" in report and 'case differs from registered "Tiger42x"' in report
    assert "'Panda77y' used more than one variant: A, B" in report
    assert "'Quiet01z' registered" in report and "no sessions yet" in report
    # Panda77y used two variants, so only Tiger42x counts towards the split.
    assert "A = 1, B = 0" in report


def test_status_on_empty_database(db):
    with db() as s:
        report = build_report(s)
    assert "Registered participants: 0" in report
    assert "Nothing." in report


def test_export_leaves_out_test_sessions_and_identities(client, db, tmp_path):
    small_study(client)
    with db() as s:
        written = export(s, tmp_path)
    assert "identities.csv" not in written
    assert not (tmp_path / "identities.csv").exists()

    sessions = rows(tmp_path / "sessions.csv")
    assert len(sessions) == 5
    assert {r["variant"] for r in sessions} == {"A", "B"}
    events = rows(tmp_path / "posture_events.csv")
    assert len(events) == sum(len(load(k)["events"]) for k in
                              ["clean", "gaps", "clean", "clean", "clean"])
    participants = rows(tmp_path / "participants.csv")
    assert len(participants) == 3
    assert "email" not in participants[0]


def test_export_with_identities_and_tests(client, db, tmp_path):
    small_study(client)
    with db() as s:
        written = export(s, tmp_path, include_test=True, with_identities=True)
    assert written["sessions.csv"] == 6
    ids = rows(tmp_path / "identities.csv")
    assert {r["email"] for r in ids} == {"test@example.com", "p@example.com",
                                         "q@example.com"}
    with db() as s:
        assert written["posture_events.csv"] == s.query(models.PostureEvent).count()

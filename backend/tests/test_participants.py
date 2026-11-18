"""POST /api/participants, GET /onboarding, and refusing sessions from
unregistered IDs.

`form_record` has the shape study/participant_onboarding.html sends: every
value a string, consents "yes"/"no".
"""

import pytest

from app import main, models

from .conftest import count, load


def form_record(**overrides):
    record = {
        "user_id": "Tiger42x",
        "submitted_at": "2026-11-18T10:00:00.000Z",
        "form_version": "1.3",
        "consent_read": "yes",
        "consent_camera": "yes",
        "consent_upload": "yes",
        "consent_pseudonymous": "yes",
        "consent_withdraw": "yes",
        "consent_age": "yes",
        "consent_voluntary": "yes",
        "consent_followup": "no",
        "consent_future": "yes",
        "consent_quotes": "no",
        "full_name": "Test Person",
        "email": "test@example.com",
        "signature": "Test Person",
        "signed_date": "2026-11-18",
        "age": "24",
        "occupation": "Student",
        "screen_total": "6-8 h",
        "screen_phone": "3-4 h",
        "pain_freq": "Sometimes",
        "pain_area": "Neck; Upper back",
        "pain_now": "3",
        "pain_treatment": "No",
        "desk_setup": "Desk",
        "chair": "Office chair",
        "monitor_height": "Below eye level",
        "phone_hold": "Below chest",
        "posture_aware": "Sometimes",
        "phone_model": "Samsung Galaxy A54",
        "android_version": "14",
    }
    record.update(overrides)
    return record


def register(client, **overrides):
    return client.post("/api/participants", json=form_record(**overrides))


# ── Registration ────────────────────────────────────────────────────────────

def test_registration_is_stored_with_identity_kept_apart(client, db):
    r = register(client)
    assert r.status_code == 200, r.text
    assert r.json() == {"ok": True}
    with db() as s:
        p = s.get(models.Participant, "Tiger42x")
        assert p.age == 24 and p.pain_now == 3
        assert p.consent_future is True and p.consent_quotes is False
        assert not hasattr(p, "email")
        ident = s.get(models.ParticipantIdentity, "Tiger42x")
        assert ident.email == "test@example.com"


def test_unanswered_optional_fields_are_stored_empty(client, db):
    assert register(client, occupation="", pain_now="").status_code == 200
    with db() as s:
        p = s.get(models.Participant, "Tiger42x")
        assert p.occupation is None and p.pain_now is None


def test_duplicate_id_is_refused_ignoring_case(client, db):
    assert register(client).status_code == 200
    r = register(client, user_id="TIGER42X", email="other@example.com")
    assert r.status_code == 409
    assert r.json() == {"ok": False, "error": "duplicate user_id"}
    assert count(db, models.Participant) == 1


@pytest.mark.parametrize("user_id", ["", "ab12c", "ab 12cd", "PG-E8XM-H06Y", "a" * 21])
def test_bad_id_is_refused(client, db, user_id):
    r = register(client, user_id=user_id)
    assert r.status_code == 422
    assert r.json() == {"ok": False, "error": "invalid user_id"}
    assert count(db, models.Participant) == 0


def test_spaces_around_id_are_trimmed(client, db):
    assert register(client, user_id="  Tiger42x ").status_code == 200
    with db() as s:
        assert s.get(models.Participant, "Tiger42x") is not None


def test_missing_required_consent_is_refused(client, db):
    r = register(client, consent_camera="no")
    assert r.status_code == 422
    assert "consent_camera" in r.json()["error"]
    assert count(db, models.Participant) == 0
    assert count(db, models.ParticipantIdentity) == 0


def test_under_18_is_refused(client):
    assert register(client, age="17").status_code == 422


def test_missing_identity_is_refused(client):
    assert register(client, full_name="").status_code == 422


# ── Onboarding form ─────────────────────────────────────────────────────────

def test_onboarding_form_is_served(client):
    r = client.get("/onboarding")
    assert r.status_code == 200
    assert "text/html" in r.headers["content-type"]
    assert '"/api/participants"' in r.text


def test_missing_form_file_is_404(client, monkeypatch, tmp_path):
    monkeypatch.setattr(main, "ONBOARDING_FORM", tmp_path / "nope.html")
    assert client.get("/onboarding").status_code == 404


# ── Sessions from unregistered IDs ──────────────────────────────────────────

def test_unregistered_session_is_accepted_when_check_is_off(client, monkeypatch):
    monkeypatch.delenv("REQUIRE_REGISTERED_USER", raising=False)
    assert client.post("/api/sessions", json=load("clean")).status_code == 200


def test_unregistered_session_is_refused_when_check_is_on(client, db, monkeypatch):
    monkeypatch.setenv("REQUIRE_REGISTERED_USER", "true")
    r = client.post("/api/sessions", json=load("clean"))
    assert r.status_code == 422
    assert "not registered" in r.text
    assert count(db, models.Session) == 0


def test_registered_session_is_accepted_when_check_is_on(client, monkeypatch):
    monkeypatch.setenv("REQUIRE_REGISTERED_USER", "true")
    assert register(client).status_code == 200
    assert client.post("/api/sessions", json=load("clean")).status_code == 200


def test_registration_check_is_case_sensitive(client, monkeypatch):
    # Registered "Tiger42x", but the app was given "TIGER42X": the sessions
    # would match no consent record, so they are refused.
    monkeypatch.setenv("REQUIRE_REGISTERED_USER", "true")
    assert register(client).status_code == 200
    body = load("clean")
    body["user_id"] = "TIGER42X"
    assert client.post("/api/sessions", json=body).status_code == 422

"""PostureGuard study server.

    POST /api/sessions       one finished session, as in study/API_SCHEMA.md
    POST /api/participants   one onboarding form submission
    GET  /onboarding         the onboarding form itself
    GET  /health             liveness check

Run locally:  uvicorn app.main:app --reload   (from the backend/ folder)
"""

import os
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

from fastapi import Body, Depends, FastAPI, Header, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from pydantic import ValidationError
from sqlalchemy import insert, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session as DbSession

from . import models
from .db import SessionLocal, engine
from .schemas import Registration, SessionUpload

# Served at /onboarding. In Docker, compose mounts the repo's copy here.
ONBOARDING_FORM = Path(os.environ.get(
    "ONBOARDING_FORM",
    Path(__file__).resolve().parents[2] / "study" / "participant_onboarding.html",
))

IDENTITY_FIELDS = ("full_name", "email", "signature", "signed_date")


def require_registered() -> bool:
    """REQUIRE_REGISTERED_USER=true refuses sessions whose user_id has no
    onboarding registration. Off by default so test devices can upload
    before anyone has registered; turn it on before recruiting."""
    return os.environ.get("REQUIRE_REGISTERED_USER", "").lower() in ("1", "true", "yes")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # Creates missing tables; never alters or drops existing ones.
    models.Base.metadata.create_all(engine)
    yield


app = FastAPI(title="PostureGuard study server", lifespan=lifespan)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@app.get("/health")
def health():
    return {"ok": True}


@app.get("/onboarding", include_in_schema=False)
def onboarding_form():
    if not ONBOARDING_FORM.is_file():
        raise HTTPException(404, "onboarding form not installed")
    return FileResponse(ONBOARDING_FORM, media_type="text/html")


def _refuse(status: int, error: str):
    # The form reads {"ok": false, "error": ...} whatever the status code.
    return JSONResponse({"ok": False, "error": error}, status_code=status)


@app.post("/api/participants")
def register_participant(body: dict = Body(...), db: DbSession = Depends(get_db)):
    try:
        reg = Registration.model_validate(body)
    except ValidationError as e:
        if any(err["loc"][:1] == ("user_id",) for err in e.errors()):
            return _refuse(422, "invalid user_id")
        return _refuse(422, "; ".join(err["msg"] for err in e.errors()))

    def duplicate():
        return db.execute(select(models.Participant.user_id).filter_by(
            user_id_lower=reg.user_id.lower())).first() is not None

    if duplicate():
        # Participants choose their own ID, so this does happen. The form
        # asks them to pick another one.
        return _refuse(409, "duplicate user_id")

    data = reg.model_dump()
    identity = {k: data.pop(k) for k in IDENTITY_FIELDS}
    db.add(models.Participant(user_id_lower=reg.user_id.lower(), **data))
    db.add(models.ParticipantIdentity(user_id=reg.user_id, **identity))
    try:
        db.commit()
    except IntegrityError:
        # Two people submitted the same ID at the same moment.
        db.rollback()
        if duplicate():
            return _refuse(409, "duplicate user_id")
        raise
    return {"ok": True}


@app.post("/api/sessions")
def upload_session(
    body: SessionUpload,
    db: DbSession = Depends(get_db),
    x_device_id: Optional[str] = Header(default=None, max_length=64),
):
    key = (body.user_id, body.session_id)

    # Exact match, case included: the app stores the ID as typed, so a
    # session from "Tiger42X" must not count for registered "Tiger42x".
    if require_registered() and db.get(models.Participant, body.user_id) is None:
        raise HTTPException(422, "user_id is not registered")

    # The app retries until it gets a 2xx, so the same session can arrive
    # twice after a lost response. Answer ok and keep the first copy.
    if db.get(models.Session, key) is not None:
        return {"ok": True, "duplicate": True}

    s, d, i, m = body.session, body.device, body.integrity, body.device_metrics_summary
    db.add(
        models.Session(
            user_id=body.user_id,
            session_id=body.session_id,
            variant=body.variant,
            app_version=body.app_version,
            device_id=x_device_id,
            started_at=s.started_at,
            ended_at=s.ended_at,
            duration_seconds=s.duration_seconds,
            good_posture_percent=s.good_posture_percent,
            longest_streak_seconds=s.longest_streak_seconds,
            worst_moment_timestamp=s.worst_moment_timestamp,
            manufacturer=d.manufacturer,
            device_model=d.model,
            android_version=d.android_version,
            cpu_cores=d.cpu_cores,
            foreground_fps=body.detection.foreground_fps,
            pip_fps=body.detection.pip_fps,
            is_valid=i.is_valid,
            gap_count=i.gap_count,
            missing_count=i.missing_count,
            metrics_sample_count=m.sample_count,
            start_battery_percent=m.start_battery_percent,
            end_battery_percent=m.end_battery_percent,
            battery_drop_percent=m.battery_drop_percent,
            discharge_seconds=m.discharge_seconds,
            battery_percent_per_hour=m.battery_percent_per_hour,
            charged_during_session=m.charged_during_session,
            avg_cpu_percent=m.avg_cpu_percent,
            max_cpu_percent=m.max_cpu_percent,
            avg_battery_temp_c=m.avg_battery_temp_c,
            max_battery_temp_c=m.max_battery_temp_c,
            worst_thermal_status=m.worst_thermal_status,
            pip_percent=m.pip_percent,
            background_percent=m.background_percent,
            power_save_percent=m.power_save_percent,
        )
    )
    try:
        db.flush()
        # Bulk inserts: a 60-minute session is ~3,600 event rows.
        db.execute(
            insert(models.PostureEvent),
            [{"user_id": key[0], "session_id": key[1], "t": e.t, "status": e.status}
             for e in body.events],
        )
        if body.device_metrics:
            db.execute(
                insert(models.DeviceMetric),
                [{"user_id": key[0], "session_id": key[1], **r.model_dump()}
                 for r in body.device_metrics],
            )
        db.commit()
    except IntegrityError:
        # Two copies of the same retry arrived at once; the other one won.
        db.rollback()
        if db.execute(select(models.Session).filter_by(
                user_id=key[0], session_id=key[1])).first() is not None:
            return {"ok": True, "duplicate": True}
        raise

    return {"ok": True}

"""PostureGuard study server.

    POST /api/sessions   one finished session, as in study/API_SCHEMA.md
    GET  /health         liveness check

Run locally:  uvicorn app.main:app --reload   (from the backend/ folder)
"""

from contextlib import asynccontextmanager
from typing import Optional

from fastapi import Depends, FastAPI, Header
from sqlalchemy import insert, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session as DbSession

from . import models
from .db import SessionLocal, engine
from .schemas import SessionUpload


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


@app.post("/api/sessions")
def upload_session(
    body: SessionUpload,
    db: DbSession = Depends(get_db),
    x_device_id: Optional[str] = Header(default=None, max_length=64),
):
    key = (body.user_id, body.session_id)

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

"""Export the study data to CSV for analysis.

    docker compose exec api python -m scripts.export /srv/export
    docker compose cp api:/srv/export ./export          (copy it off the container)

Writes sessions.csv, posture_events.csv, device_metrics.csv and
participants.csv into the given folder. All four join on user_id
(and session_id for the per-session tables).

Variant C sessions are internal tests and left out unless --include-test.
Names, emails and signatures are left out unless --with-identities, which
writes them to a separate identities.csv: keep that file apart from the
research data, it is the restricted linking list.
"""

import argparse
import csv
from pathlib import Path

from sqlalchemy import select

from app import models
from app.db import SessionLocal


def _columns(model):
    return [c.name for c in model.__table__.columns]


def _write(path: Path, model, rows) -> int:
    cols = _columns(model)
    n = 0
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(cols)
        for row in rows:
            w.writerow([getattr(row, c) for c in cols])
            n += 1
    return n


def export(db, out: Path, include_test=False, with_identities=False) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    written = {}

    def per_session(model):
        q = select(model)
        if not include_test:
            q = q.join(models.Session, (models.Session.user_id == model.user_id)
                       & (models.Session.session_id == model.session_id)
                       ).where(models.Session.variant != "C")
        # ~3,600 event rows per session-hour: stream instead of loading all.
        return db.scalars(q.order_by(model.user_id, model.session_id, model.t)
                          .execution_options(yield_per=5000))

    sessions = select(models.Session).order_by(models.Session.user_id,
                                               models.Session.session_id)
    if not include_test:
        sessions = sessions.where(models.Session.variant != "C")
    written["sessions.csv"] = _write(out / "sessions.csv", models.Session,
                                     db.scalars(sessions))
    written["posture_events.csv"] = _write(out / "posture_events.csv",
                                           models.PostureEvent,
                                           per_session(models.PostureEvent))
    written["device_metrics.csv"] = _write(out / "device_metrics.csv",
                                           models.DeviceMetric,
                                           per_session(models.DeviceMetric))
    written["participants.csv"] = _write(
        out / "participants.csv", models.Participant,
        db.scalars(select(models.Participant).order_by(models.Participant.user_id)))
    if with_identities:
        written["identities.csv"] = _write(
            out / "identities.csv", models.ParticipantIdentity,
            db.scalars(select(models.ParticipantIdentity)
                       .order_by(models.ParticipantIdentity.user_id)))
    return written


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("out", type=Path, help="folder to write the CSV files into")
    ap.add_argument("--include-test", action="store_true",
                    help="also export variant C (internal test) sessions")
    ap.add_argument("--with-identities", action="store_true",
                    help="also write identities.csv (names, emails): restricted")
    args = ap.parse_args()
    with SessionLocal() as db:
        written = export(db, args.out, args.include_test, args.with_identities)
    for name, n in written.items():
        print(f"{args.out / name}: {n} rows")


if __name__ == "__main__":
    main()

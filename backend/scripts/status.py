"""Study status, for checking during data collection.

    docker compose exec api python -m scripts.status     (on the server)
    .venv/bin/python -m scripts.status                   (locally, from backend/)

Prints the problems the plan says to catch while the study runs, not at the
end: sessions whose user_id matches no registration, participants using
more than one variant, registered participants with no sessions yet, and
the A/B split. Read-only.
"""

from collections import defaultdict
from datetime import datetime, timezone

from sqlalchemy import select

from app import models
from app.db import SessionLocal


def build_report(db) -> str:
    registered = {p.user_id: p for p in db.scalars(select(models.Participant))}
    by_lower = {uid.lower(): uid for uid in registered}

    per_user = defaultdict(lambda: {"sessions": 0, "gap_sessions": 0, "seconds": 0,
                                    "variants": set(), "last": None})
    for s in db.scalars(select(models.Session).where(models.Session.variant != "C")):
        u = per_user[s.user_id]
        u["sessions"] += 1
        u["gap_sessions"] += 0 if s.is_valid else 1
        u["seconds"] += s.duration_seconds
        u["variants"].add(s.variant)
        if u["last"] is None or s.received_at > u["last"]:
            u["last"] = s.received_at
    test_sessions = len(db.scalars(
        select(models.Session.session_id).where(models.Session.variant == "C")).all())

    out = []
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    total = sum(u["sessions"] for u in per_user.values())
    gaps = sum(u["gap_sessions"] for u in per_user.values())
    out.append(f"PostureGuard study status — {now}")
    out.append(f"Registered participants: {len(registered)}")
    out.append(f"Sessions (A/B): {total}"
               + (f", of which gap-only: {gaps} ({100 * gaps / total:.0f}%)" if total else ""))
    if test_sessions:
        out.append(f"Variant C test sessions, ignored below: {test_sessions}")

    groups = defaultdict(list)
    for uid, u in per_user.items():
        if uid in registered and len(u["variants"]) == 1:
            groups[next(iter(u["variants"]))].append(uid)
    out.append(f"A/B split (registered, single variant): "
               f"A = {len(groups['A'])}, B = {len(groups['B'])}")

    out.append("")
    out.append("── Needs attention ──")
    problems = 0

    for uid in sorted(set(per_user) - set(registered)):
        problems += 1
        hint = by_lower.get(uid.lower())
        why = f'case differs from registered "{hint}"' if hint else "no registration"
        out.append(f"  Unregistered user_id {uid!r}: {per_user[uid]['sessions']} "
                   f"session(s), {why}")

    for uid, u in sorted(per_user.items()):
        if len(u["variants"]) > 1:
            problems += 1
            out.append(f"  {uid!r} used more than one variant: "
                       f"{', '.join(sorted(u['variants']))}")

    for uid in sorted(set(registered) - set(per_user)):
        problems += 1
        out.append(f"  {uid!r} registered "
                   f"{registered[uid].received_at:%Y-%m-%d} but has no sessions yet")

    if not problems:
        out.append("  Nothing.")

    out.append("")
    out.append("── Per participant ──")
    out.append(f"  {'user_id':<20} {'var':<4} {'sessions':>8} {'gap-only':>8} "
               f"{'hours':>6}  last upload")
    for uid, u in sorted(per_user.items()):
        mark = "" if uid in registered else "  (unregistered)"
        out.append(f"  {uid:<20} {'/'.join(sorted(u['variants'])):<4} "
                   f"{u['sessions']:>8} {u['gap_sessions']:>8} "
                   f"{u['seconds'] / 3600:>6.1f}  {u['last']:%Y-%m-%d %H:%M}{mark}")
    return "\n".join(out)


def main():
    with SessionLocal() as db:
        print(build_report(db))


if __name__ == "__main__":
    main()

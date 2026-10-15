"""Database connection. Set DATABASE_URL to point at PostgreSQL, e.g.

    postgresql+psycopg://postureguard:secret@db:5432/postureguard

Without it, a local SQLite file is used, which is enough for development.
"""

import os

from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker

DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:///./postureguard.db")


def make_engine(url: str = DATABASE_URL):
    if url.startswith("sqlite"):
        engine = create_engine(url, connect_args={"check_same_thread": False})

        # SQLite ignores foreign keys unless asked, PostgreSQL always enforces
        # them; keep the two behaving the same.
        @event.listens_for(engine, "connect")
        def _fk_on(dbapi_conn, _):
            dbapi_conn.execute("PRAGMA foreign_keys=ON")

        return engine
    return create_engine(url, pool_pre_ping=True)


engine = make_engine()
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)

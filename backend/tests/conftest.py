import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import sessionmaker

from app import models
from app.db import make_engine
from app.main import app, get_db

FIXTURES = Path(__file__).parent / "fixtures"


def load(name):
    return json.loads((FIXTURES / f"app_payload_{name}.json").read_text())


def count(Local, model):
    with Local() as s:
        return s.scalar(select(func.count()).select_from(model))


@pytest.fixture
def db(tmp_path):
    engine = make_engine(f"sqlite:///{tmp_path / 'test.db'}")
    models.Base.metadata.create_all(engine)
    Local = sessionmaker(bind=engine, expire_on_commit=False)

    def override():
        s = Local()
        try:
            yield s
        finally:
            s.close()

    app.dependency_overrides[get_db] = override
    yield Local
    app.dependency_overrides.clear()


@pytest.fixture
def client(db):
    return TestClient(app)

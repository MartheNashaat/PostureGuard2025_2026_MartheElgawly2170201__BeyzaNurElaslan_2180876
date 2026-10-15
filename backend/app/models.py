"""Tables from the "Suggested database tables" section of study/API_SCHEMA.md.

Research data only. Names and emails from the onboarding form never go in
these tables; they live in the restricted linking list (see the plan).
"""

from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger,
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKeyConstraint,
    Index,
    Integer,
    SmallInteger,
    String,
)
from sqlalchemy.orm import declarative_base

Base = declarative_base()


def _utcnow():
    return datetime.now(timezone.utc)


class Session(Base):
    """One row per uploaded session; device_metrics_summary is flattened in."""

    __tablename__ = "sessions"

    # session_id is unique per device only (it is the start time in ms), so
    # the key is the pair.
    user_id = Column(String(20), primary_key=True)
    session_id = Column(String(64), primary_key=True)
    variant = Column(String(1), nullable=False)
    app_version = Column(String(64))
    device_id = Column(String(64))  # X-Device-Id header: random per install

    started_at = Column(BigInteger)
    ended_at = Column(BigInteger)
    duration_seconds = Column(Integer, nullable=False)
    good_posture_percent = Column(Float, nullable=False)
    longest_streak_seconds = Column(Integer, nullable=False)
    worst_moment_timestamp = Column(BigInteger)

    manufacturer = Column(String(64))
    device_model = Column(String(64))
    android_version = Column(String(32))
    cpu_cores = Column(Integer)

    foreground_fps = Column(Float)
    pip_fps = Column(Float)

    is_valid = Column(Boolean, nullable=False)
    gap_count = Column(Integer, nullable=False)
    missing_count = Column(Integer, nullable=False)

    metrics_sample_count = Column(Integer)
    start_battery_percent = Column(Float)
    end_battery_percent = Column(Float)
    battery_drop_percent = Column(Float)
    discharge_seconds = Column(Integer)
    battery_percent_per_hour = Column(Float)
    charged_during_session = Column(Boolean)
    avg_cpu_percent = Column(Float)
    max_cpu_percent = Column(Float)
    avg_battery_temp_c = Column(Float)
    max_battery_temp_c = Column(Float)
    worst_thermal_status = Column(String(16))
    pip_percent = Column(Float)
    background_percent = Column(Float)
    power_save_percent = Column(Float)

    received_at = Column(DateTime(timezone=True), nullable=False, default=_utcnow)


class PostureEvent(Base):
    """One row per second: the posture zone."""

    __tablename__ = "posture_events"
    __table_args__ = (
        ForeignKeyConstraint(
            ["user_id", "session_id"],
            ["sessions.user_id", "sessions.session_id"],
            ondelete="CASCADE",
        ),
    )

    user_id = Column(String(20), primary_key=True)
    session_id = Column(String(64), primary_key=True)
    t = Column(BigInteger, primary_key=True)
    status = Column(SmallInteger, nullable=False)  # 0 good, 1 warning, 2 bad


class DeviceMetric(Base):
    """One row every 15 s: battery, temperature, CPU, app state."""

    __tablename__ = "device_metrics"
    __table_args__ = (
        ForeignKeyConstraint(
            ["user_id", "session_id"],
            ["sessions.user_id", "sessions.session_id"],
            ondelete="CASCADE",
        ),
        Index("ix_device_metrics_session", "user_id", "session_id"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(String(20), nullable=False)
    session_id = Column(String(64), nullable=False)
    t = Column(BigInteger, nullable=False)
    battery_percent = Column(Float)
    battery_temperature_c = Column(Float)
    is_charging = Column(Boolean, nullable=False)
    thermal_status = Column(String(16))
    cpu_percent = Column(Float)
    is_screen_on = Column(Boolean, nullable=False)
    is_power_save = Column(Boolean, nullable=False)
    app_state = Column(String(16))

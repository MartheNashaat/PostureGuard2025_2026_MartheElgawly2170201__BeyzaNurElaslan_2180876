"""Tables from the "Database tables" section of study/API_SCHEMA.md, plus
the onboarding form's registrations.

Names, emails and signatures go only in `participant_identities`, the
restricted linking list. Every other table is research data.
"""

from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger,
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
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


class Participant(Base):
    """One row per onboarding form submission: consent and demographics."""

    __tablename__ = "participants"

    user_id = Column(String(20), primary_key=True)  # exactly as typed
    # IDs are unique ignoring case, so look-alike IDs can't be mixed up when
    # joining sessions to consent records.
    user_id_lower = Column(String(20), nullable=False, unique=True)
    received_at = Column(DateTime(timezone=True), nullable=False, default=_utcnow)
    submitted_at = Column(String(40))  # the browser's clock, as sent
    form_version = Column(String(16))

    consent_read = Column(Boolean, nullable=False)
    consent_camera = Column(Boolean, nullable=False)
    consent_upload = Column(Boolean, nullable=False)
    consent_pseudonymous = Column(Boolean, nullable=False)
    consent_withdraw = Column(Boolean, nullable=False)
    consent_age = Column(Boolean, nullable=False)
    consent_voluntary = Column(Boolean, nullable=False)
    consent_followup = Column(Boolean, nullable=False)
    consent_future = Column(Boolean, nullable=False)
    consent_quotes = Column(Boolean, nullable=False)

    age = Column(Integer)
    occupation = Column(String(200))
    screen_total = Column(String(64))
    screen_phone = Column(String(64))
    pain_freq = Column(String(64))
    pain_area = Column(String(200))
    pain_now = Column(Integer)
    pain_treatment = Column(String(64))
    desk_setup = Column(String(64))
    chair = Column(String(64))
    monitor_height = Column(String(64))
    phone_hold = Column(String(64))
    posture_aware = Column(String(64))

    phone_model = Column(String(100))
    android_version = Column(String(32))


class ParticipantIdentity(Base):
    """Restricted linking list: who a user_id is. Needed for withdrawal
    requests; never exported with the research data."""

    __tablename__ = "participant_identities"

    user_id = Column(
        String(20),
        ForeignKey("participants.user_id", ondelete="CASCADE"),
        primary_key=True,
    )
    full_name = Column(String(200), nullable=False)
    email = Column(String(200), nullable=False)
    signature = Column(String(200), nullable=False)
    signed_date = Column(String(10), nullable=False)

"""Request body for POST /api/sessions — the payload in study/API_SCHEMA.md.

Field names and types follow what the app's `buildSessionPayload`
(lib/services/upload_payload.dart) actually produces. Unknown fields are
ignored, so the app can add fields without breaking older servers.
"""

from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator

# Same rule as ParticipantService in the app and the onboarding form:
# 6+ letters/numbers, case-sensitive. 20 is the app's input field limit.
USER_ID_PATTERN = r"^[A-Za-z0-9]{6,20}$"


class _Model(BaseModel):
    model_config = ConfigDict(extra="ignore")


class SessionInfo(_Model):
    started_at: Optional[int] = None
    ended_at: Optional[int] = None
    duration_seconds: int
    good_posture_percent: float
    longest_streak_seconds: int
    worst_moment_timestamp: Optional[int] = None


class DeviceInfo(_Model):
    manufacturer: Optional[str] = None
    model: Optional[str] = None
    android_version: Optional[str] = None
    cpu_cores: Optional[int] = None


class DetectionInfo(_Model):
    foreground_fps: Optional[float] = None
    pip_fps: Optional[float] = None


class IntegrityInfo(_Model):
    is_valid: bool
    gap_count: int = Field(ge=0)
    missing_count: int = Field(ge=0)


class Event(_Model):
    t: int
    status: int = Field(ge=0, le=2)  # 0 good, 1 warning, 2 bad


class DeviceMetric(_Model):
    t: int
    battery_percent: Optional[float] = None
    battery_temperature_c: Optional[float] = None
    is_charging: bool = False
    thermal_status: Optional[str] = None
    cpu_percent: Optional[float] = None
    is_screen_on: bool = False
    is_power_save: bool = False
    app_state: Optional[str] = None


class DeviceMetricsSummary(_Model):
    sample_count: Optional[int] = None
    duration_seconds: Optional[int] = None
    start_battery_percent: Optional[float] = None
    end_battery_percent: Optional[float] = None
    battery_drop_percent: Optional[float] = None
    discharge_seconds: Optional[int] = None
    battery_percent_per_hour: Optional[float] = None
    charged_during_session: Optional[bool] = None
    avg_cpu_percent: Optional[float] = None
    max_cpu_percent: Optional[float] = None
    avg_battery_temp_c: Optional[float] = None
    max_battery_temp_c: Optional[float] = None
    worst_thermal_status: Optional[str] = None
    pip_percent: Optional[float] = None
    background_percent: Optional[float] = None
    power_save_percent: Optional[float] = None


class SessionUpload(_Model):
    user_id: str = Field(pattern=USER_ID_PATTERN)
    session_id: str = Field(min_length=1, max_length=64)
    # C (both) is hidden from participants but still accepted, so internal
    # test sessions can be uploaded; analysis excludes them.
    variant: str = Field(pattern=r"^[ABC]$")
    app_version: Optional[str] = None
    session: SessionInfo
    device: DeviceInfo = DeviceInfo()
    detection: DetectionInfo = DetectionInfo()
    integrity: IntegrityInfo
    events: List[Event] = Field(min_length=1)
    device_metrics: List[DeviceMetric] = []
    device_metrics_summary: DeviceMetricsSummary = DeviceMetricsSummary()

    @model_validator(mode="after")
    def _check_integrity(self) -> "SessionUpload":
        # Decision of 15 Oct 2026: only clean and gap-only sessions are sent.
        # The app decides that on the phone; these checks catch a client that
        # skipped the gate.
        times = [e.t for e in self.events]
        if any(b <= a for a, b in zip(times, times[1:])):
            raise ValueError("events must be in strictly increasing time order")
        if self.integrity.missing_count > 0:
            raise ValueError("sessions with missing timestamps are not accepted")
        if not self.integrity.is_valid and self.integrity.gap_count == 0:
            raise ValueError(
                "is_valid is false but gap_count is 0; only gap-only "
                "sessions may be uploaded as invalid"
            )
        return self

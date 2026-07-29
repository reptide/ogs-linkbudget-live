"""Open-Meteo access using only the Python standard library."""

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import json
import math
import os
import ssl
from urllib.parse import urlencode
from urllib.request import urlopen

from .physics import classify_attenuation

API_URL = "https://api.open-meteo.com/v1/forecast"
SYSTEM_CA_FILES = (
    "/etc/ssl/cert.pem",
    "/etc/ssl/certs/ca-certificates.crt",
    "/etc/pki/tls/certs/ca-bundle.crt",
)


@dataclass
class CurrentWeather:
    visibility_km: float
    attenuation_type: str
    weather_code: float
    cloud_cover_pct: float
    wind_speed_ms: float
    temperature_c: float
    time_utc: datetime
    source: str


@dataclass
class WeatherHistory:
    times_utc: list[datetime]
    relative_seconds: list[float]
    visibility_km: list[float]
    weather_codes: list[float]
    attenuation_types: list[str]
    source: str


def _read_json(params: dict[str, str | int | float], timeout: float = 10.0) -> dict:
    url = f"{API_URL}?{urlencode(params)}"
    verify_paths = ssl.get_default_verify_paths()
    if verify_paths.cafile:
        context = ssl.create_default_context()
    else:
        system_ca = next((path for path in SYSTEM_CA_FILES if os.path.isfile(path)), None)
        context = ssl.create_default_context(cafile=system_ca)
    with urlopen(url, timeout=timeout, context=context) as response:
        return json.loads(response.read().decode("utf-8"))


def _parse_utc(value: str) -> datetime:
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def fetch_current_weather(latitude: float, longitude: float) -> CurrentWeather:
    """Retrieve the latest weather, falling back to clear 10 km visibility."""
    try:
        response = _read_json(
            {
                "latitude": latitude,
                "longitude": longitude,
                "current": (
                    "temperature_2m,wind_speed_10m,weather_code,"
                    "cloud_cover,visibility"
                ),
                "timezone": "UTC",
                "wind_speed_unit": "ms",
            }
        )
        current = response["current"]
        code = float(current["weather_code"])
        return CurrentWeather(
            visibility_km=float(current["visibility"]) / 1000.0,
            attenuation_type=classify_attenuation(code),
            weather_code=code,
            cloud_cover_pct=float(current["cloud_cover"]),
            wind_speed_ms=float(current["wind_speed_10m"]),
            temperature_c=float(current["temperature_2m"]),
            time_utc=_parse_utc(current["time"]),
            source="open-meteo-live",
        )
    except Exception:
        return CurrentWeather(
            visibility_km=10.0,
            attenuation_type="clear",
            weather_code=math.nan,
            cloud_cover_pct=math.nan,
            wind_speed_ms=math.nan,
            temperature_c=math.nan,
            time_utc=datetime.now(timezone.utc),
            source="fallback-default",
        )


def fetch_weather_history(
    latitude: float,
    longitude: float,
    duration_seconds: float,
) -> WeatherHistory:
    """Retrieve recent 15-minute weather ending at the latest API timestep."""
    if duration_seconds <= 0.0:
        raise ValueError("Duration must be positive.")

    sample_period_seconds = 15 * 60
    past_samples = math.ceil(duration_seconds / sample_period_seconds)
    try:
        response = _read_json(
            {
                "latitude": latitude,
                "longitude": longitude,
                "minutely_15": "visibility,weather_code",
                "past_minutely_15": past_samples,
                "forecast_minutely_15": 1,
                "timezone": "UTC",
            }
        )
        series = response["minutely_15"]
        times = [_parse_utc(value) for value in series["time"]]
        visibility = [float(value) / 1000.0 for value in series["visibility"]]
        codes = [float(value) for value in series["weather_code"]]
        end = times[-1]
        start = end - timedelta(seconds=duration_seconds)
        relative = [(sample - start).total_seconds() for sample in times]
        return WeatherHistory(
            times_utc=times,
            relative_seconds=relative,
            visibility_km=visibility,
            weather_codes=codes,
            attenuation_types=[classify_attenuation(code) for code in codes],
            source="open-meteo-15-minute-history",
        )
    except Exception:
        end = datetime.now(timezone.utc)
        return WeatherHistory(
            times_utc=[end - timedelta(seconds=duration_seconds), end],
            relative_seconds=[0.0, duration_seconds],
            visibility_km=[10.0, 10.0],
            weather_codes=[math.nan, math.nan],
            attenuation_types=["clear", "clear"],
            source="fallback-default",
        )

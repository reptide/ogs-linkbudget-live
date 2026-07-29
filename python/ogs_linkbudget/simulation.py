"""Snapshot and continuous link-budget engines."""

from bisect import bisect_right
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import math
import random

from .config import SimulatorConfig, Terminal
from .physics import (
    aperture_gain_db,
    aperture_gain_linear,
    atmospheric_loss_db,
    free_space_path_loss_db,
    pointing_loss_db,
    slant_range_circular_orbit,
)
from .weather import fetch_current_weather, fetch_weather_history


@dataclass
class SnapshotResult:
    link_type: str
    margin_db: float
    ideal_margin_db: float
    path_loss_db: float
    distance_km: float
    atmospheric_loss_db: float
    geometric_loss_db: float
    mie_loss_db: float
    visibility_km: float | None
    attenuation_type: str | None
    weather_source: str | None

    @property
    def successful(self) -> bool:
        return self.margin_db > 0.0


@dataclass
class ContinuousResult:
    link_type: str
    elapsed_seconds: list[float]
    plot_times_utc: list[datetime] | None
    time_axis_label: str
    margins_db: list[float]
    ideal_margin_db: float
    outage_rate_pct: float
    jitter_model: str
    elevation_deg: float | None
    weather_description: str


def _terminals(config: SimulatorConfig) -> tuple[Terminal, Terminal]:
    link_type = config.link.link_type
    if link_type == "uplink":
        return config.ground, config.satellite_a
    if link_type == "inter-satellite":
        return config.satellite_a, config.satellite_b
    if link_type == "downlink":
        return config.satellite_a, config.ground
    raise ValueError(f"Unsupported link type: {link_type}")


def _distance_m(config: SimulatorConfig) -> tuple[float, float | None]:
    if config.link.link_type == "inter-satellite":
        return config.link.satellite_distance_km * 1000.0, None
    elevation = config.orbit.worst_case_elevation_deg
    distance = slant_range_circular_orbit(
        elevation,
        config.satellite_a.height_km * 1000.0,
        config.ground.height_km * 1000.0,
    )
    return distance, elevation


def _ideal_margin(
    config: SimulatorConfig,
    transmitter: Terminal,
    receiver: Terminal,
    distance_m: float,
) -> tuple[float, float]:
    wavelength = config.link.wavelength_m
    path_loss = free_space_path_loss_db(distance_m, wavelength)
    ideal_received_dbm = (
        config.link.transmit_power_dbm
        + 10.0 * math.log10(transmitter.optics_efficiency)
        + 10.0 * math.log10(receiver.optics_efficiency)
        + aperture_gain_db(transmitter.aperture_diameter_m, wavelength)
        + aperture_gain_db(receiver.aperture_diameter_m, wavelength)
        - path_loss
    )
    return ideal_received_dbm - config.link.required_power_dbm, path_loss


def run_snapshot(config: SimulatorConfig) -> SnapshotResult:
    """Calculate one deterministic link-budget condition."""
    transmitter, receiver = _terminals(config)
    distance_m, elevation = _distance_m(config)
    ideal_margin, path_loss = _ideal_margin(config, transmitter, receiver, distance_m)
    wavelength = config.link.wavelength_m

    tx_pointing_loss = pointing_loss_db(
        aperture_gain_linear(transmitter.aperture_diameter_m, wavelength),
        transmitter.pointing_error_rad,
    )
    rx_pointing_loss = pointing_loss_db(
        aperture_gain_linear(receiver.aperture_diameter_m, wavelength),
        receiver.pointing_error_rad,
    )

    total_atmosphere = geometric = mie = 0.0
    visibility = None
    attenuation = None
    weather_source = None
    if config.link.link_type != "inter-satellite":
        if config.weather.use_live:
            weather = fetch_current_weather(
                config.ground.latitude_deg, config.ground.longitude_deg
            )
            visibility = weather.visibility_km
            attenuation = weather.attenuation_type
            weather_source = weather.source
        else:
            visibility = config.weather.manual.visibility_km
            attenuation = config.weather.manual.attenuation_type
            weather_source = "manual"
        total_atmosphere, geometric, mie = atmospheric_loss_db(
            visibility,
            attenuation,
            elevation,
            config.ground.height_km,
            wavelength,
            config.link.troposphere_height_km,
            config.link.absorption_loss_db,
        )

    margin = ideal_margin - tx_pointing_loss - rx_pointing_loss - total_atmosphere
    return SnapshotResult(
        link_type=config.link.link_type,
        margin_db=margin,
        ideal_margin_db=ideal_margin,
        path_loss_db=path_loss,
        distance_km=distance_m / 1000.0,
        atmospheric_loss_db=total_atmosphere,
        geometric_loss_db=geometric,
        mie_loss_db=mie,
        visibility_km=visibility,
        attenuation_type=attenuation,
        weather_source=weather_source,
    )


def _interpolate(x_points: list[float], values: list[float], x: float) -> float:
    if len(x_points) != len(values) or len(x_points) < 2:
        raise ValueError("Interpolation requires matching arrays with at least two points.")
    index = bisect_right(x_points, x)
    if index == 0:
        left, right = 0, 1
    elif index >= len(x_points):
        left, right = len(x_points) - 2, len(x_points) - 1
    else:
        left, right = index - 1, index
    span = x_points[right] - x_points[left]
    if span == 0.0:
        return values[left]
    ratio = (x - x_points[left]) / span
    return values[left] + ratio * (values[right] - values[left])


def run_continuous(
    config: SimulatorConfig,
    duration_seconds: float,
    time_step_seconds: float = 0.1,
    jitter_model: str = "Rayleigh (No Bias)",
) -> ContinuousResult:
    """Simulate randomized pointing loss over a fixed link condition."""
    if duration_seconds <= 0.0 or time_step_seconds <= 0.0:
        raise ValueError("Duration and time step must be positive.")

    transmitter, receiver = _terminals(config)
    distance_m, elevation = _distance_m(config)
    ideal_margin, _ = _ideal_margin(config, transmitter, receiver, distance_m)
    count = int(round(duration_seconds / time_step_seconds)) + 1
    elapsed = [min(index * time_step_seconds, duration_seconds) for index in range(count)]

    wavelength = config.link.wavelength_m
    divergence = 1.22 * wavelength / transmitter.aperture_diameter_m
    beam_radius = distance_m * divergence
    sigma = math.hypot(transmitter.jitter_sigma_rad, receiver.jitter_sigma_rad)
    if sigma == 0.0:
        sigma = 1e-9
    bias = (
        config.link.boresight_bias_rad
        if "rician" in jitter_model.lower()
        else 0.0
    )

    generator = random.Random()
    tracking_loss = []
    for _ in elapsed:
        x_error = bias + generator.gauss(0.0, sigma)
        y_error = generator.gauss(0.0, sigma)
        displacement = distance_m * math.hypot(x_error, y_error)
        raw_loss = max(math.exp(-2.0 * displacement**2 / beam_radius**2), 1e-30)
        tracking_loss.append(10.0 * math.log10(raw_loss))

    plot_times = None
    time_axis_label = "Time (Seconds)"
    atmosphere: float | list[float]
    if config.link.link_type == "inter-satellite":
        atmosphere = 0.0
        weather_description = "No atmospheric loss"
    elif not config.weather.use_live:
        atmosphere = atmospheric_loss_db(
            config.weather.manual.visibility_km,
            config.weather.manual.attenuation_type,
            elevation,
            config.ground.height_km,
            wavelength,
            config.link.troposphere_height_km,
            config.link.absorption_loss_db,
        )[0]
        weather_description = (
            f"Manual: {config.weather.manual.visibility_km:.2f} km, "
            f"{config.weather.manual.attenuation_type}"
        )
    elif config.weather.continuous_mode == "Current Hold":
        weather = fetch_current_weather(
            config.ground.latitude_deg, config.ground.longitude_deg
        )
        atmosphere = atmospheric_loss_db(
            weather.visibility_km,
            weather.attenuation_type,
            elevation,
            config.ground.height_km,
            wavelength,
            config.link.troposphere_height_km,
            config.link.absorption_loss_db,
        )[0]
        start = datetime.now(timezone.utc)
        plot_times = [start + timedelta(seconds=value) for value in elapsed]
        time_axis_label = "Projected Time (UTC)"
        weather_description = (
            f"Current Hold: {weather.visibility_km:.2f} km, "
            f"{weather.attenuation_type} ({weather.source})"
        )
    else:
        history = fetch_weather_history(
            config.ground.latitude_deg,
            config.ground.longitude_deg,
            duration_seconds,
        )
        sample_losses = [
            atmospheric_loss_db(
                visibility,
                attenuation,
                elevation,
                config.ground.height_km,
                wavelength,
                config.link.troposphere_height_km,
                config.link.absorption_loss_db,
            )[0]
            for visibility, attenuation in zip(
                history.visibility_km, history.attenuation_types
            )
        ]
        atmosphere = [
            _interpolate(history.relative_seconds, sample_losses, value)
            for value in elapsed
        ]
        start = history.times_utc[-1] - timedelta(seconds=duration_seconds)
        plot_times = [start + timedelta(seconds=value) for value in elapsed]
        time_axis_label = "Historical Time (UTC)"
        weather_description = (
            f"Past Replay: {len(history.times_utc)} samples ({history.source})"
        )

    if isinstance(atmosphere, list):
        margins = [
            ideal_margin - atmosphere_loss + jitter_loss
            for atmosphere_loss, jitter_loss in zip(atmosphere, tracking_loss)
        ]
    else:
        margins = [
            ideal_margin - atmosphere + jitter_loss for jitter_loss in tracking_loss
        ]
    outage_rate = 100.0 * sum(value < 0.0 for value in margins) / len(margins)
    return ContinuousResult(
        link_type=config.link.link_type,
        elapsed_seconds=elapsed,
        plot_times_utc=plot_times,
        time_axis_label=time_axis_label,
        margins_db=margins,
        ideal_margin_db=ideal_margin,
        outage_rate_pct=outage_rate,
        jitter_model=jitter_model,
        elevation_deg=elevation,
        weather_description=weather_description,
    )


def format_snapshot(result: SnapshotResult) -> str:
    """Format snapshot output for the desktop application."""
    lines = [
        f"LINK BUDGET SNAPSHOT ({result.link_type.upper()})",
        "",
        f"Distance:                 {result.distance_km:.1f} km",
        f"Free-space path loss:     {result.path_loss_db:.2f} dB",
        f"Ideal reference margin:   {result.ideal_margin_db:.2f} dB",
    ]
    if result.visibility_km is not None:
        lines.extend(
            [
                f"Visibility:               {result.visibility_km:.2f} km",
                f"Attenuation type:         {result.attenuation_type}",
                f"Geometrical scattering:   {result.geometric_loss_db:.2f} dB",
                f"Mie scattering:           {result.mie_loss_db:.2f} dB",
                f"Total atmospheric loss:   {result.atmospheric_loss_db:.2f} dB",
                f"Weather source:            {result.weather_source}",
            ]
        )
    lines.extend(
        [
            "",
            f"Link margin:              {result.margin_db:.2f} dB",
            f"Status:                   {'SUCCESS' if result.successful else 'FAILED / RISK'}",
        ]
    )
    return "\n".join(lines)

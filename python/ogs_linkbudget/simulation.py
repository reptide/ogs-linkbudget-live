"""Snapshot and continuous link-budget engines."""

from bisect import bisect_right
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import math
import random

from .config import SimulatorConfig, Terminal
from .jitter import (
    CONFIGURED_RANDOM,
    generate_terminal_jitter,
    recommended_time_step,
    suppression_amplitude_scale,
)
from .physics import (
    aperture_gain_db,
    aperture_gain_linear,
    atmospheric_loss_db,
    free_space_path_loss_db,
    pointing_loss_db,
)
from .trajectory import resolve_trajectory
from .weather import fetch_current_weather, fetch_weather_history


@dataclass
class SnapshotResult:
    link_type: str
    margin_db: float
    ideal_margin_db: float
    outage_margin_db: float
    path_loss_db: float
    distance_km: float
    atmospheric_loss_db: float
    geometric_loss_db: float
    mie_loss_db: float
    visibility_km: float | None
    attenuation_type: str | None
    weather_source: str | None
    trajectory_source: str
    elevation_deg: float | None
    azimuth_deg: float | None
    minimum_elevation_deg: float | None
    has_access: bool

    @property
    def successful(self) -> bool:
        return self.has_access and self.margin_db >= self.outage_margin_db


@dataclass
class ContinuousResult:
    link_type: str
    elapsed_seconds: list[float]
    plot_times_utc: list[datetime] | None
    time_axis_label: str
    margins_db: list[float]
    ideal_margin_db: float
    ideal_margins_db: list[float]
    outage_margin_db: float
    outage_rate_pct: float
    no_access_rate_pct: float
    visible_link_outage_rate_pct: float
    visible_mask: list[bool]
    ranges_km: list[float]
    elevations_deg: list[float | None]
    trajectory_description: str
    jitter_model: str
    tx_jitter_profile: str
    rx_jitter_profile: str
    tx_jitter_suppression_db: float
    rx_jitter_suppression_db: float
    time_step_seconds: float
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
    if config.link.outage_margin_db < 0.0:
        raise ValueError("Required operational margin cannot be negative.")
    transmitter, receiver = _terminals(config)
    epoch = datetime.now(timezone.utc)

    if config.link.link_type == "inter-satellite":
        distance_m = config.link.satellite_distance_km * 1000.0
        elevation = None
        azimuth = None
        minimum_elevation = None
        trajectory_source = "Fixed inter-satellite range"
        has_access = True
    else:
        geometry = resolve_trajectory(config, [0.0], epoch)
        distance_m = geometry.ranges_m[0]
        elevation = geometry.elevations_deg[0]
        azimuth = geometry.azimuths_deg[0]
        minimum_elevation = config.orbit.minimum_elevation_deg
        trajectory_source = geometry.source
        has_access = geometry.visible[0]

    ideal_margin, path_loss = _ideal_margin(
        config, transmitter, receiver, distance_m
    )
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
    if config.link.link_type != "inter-satellite" and has_access:
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
            max(elevation, 0.001),
            config.ground.height_km,
            wavelength,
            config.link.troposphere_height_km,
            config.link.absorption_loss_db,
        )

    margin = (
        ideal_margin - tx_pointing_loss - rx_pointing_loss - total_atmosphere
        if has_access
        else math.nan
    )
    return SnapshotResult(
        link_type=config.link.link_type,
        margin_db=margin,
        ideal_margin_db=ideal_margin,
        outage_margin_db=config.link.outage_margin_db,
        path_loss_db=path_loss,
        distance_km=distance_m / 1000.0,
        atmospheric_loss_db=total_atmosphere,
        geometric_loss_db=geometric,
        mie_loss_db=mie,
        visibility_km=visibility,
        attenuation_type=attenuation,
        weather_source=weather_source,
        trajectory_source=trajectory_source,
        elevation_deg=elevation,
        azimuth_deg=azimuth,
        minimum_elevation_deg=minimum_elevation,
        has_access=has_access,
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


def _sample_times(duration: float, step: float) -> list[float]:
    count = math.floor(duration / step)
    values = [index * step for index in range(count + 1)]
    if not math.isclose(values[-1], duration, rel_tol=0.0, abs_tol=1e-12):
        values.append(duration)
    else:
        values[-1] = duration
    return values


def run_continuous(
    config: SimulatorConfig,
    duration_seconds: float,
    time_step_seconds: float = 0.1,
    jitter_model: str = "Rayleigh (No Bias)",
    *,
    tx_jitter_profile: str | None = None,
    rx_jitter_profile: str | None = None,
) -> ContinuousResult:
    """Simulate trajectory, atmosphere, and independent terminal jitter."""
    if duration_seconds <= 0.0 or time_step_seconds <= 0.0:
        raise ValueError("Duration and time step must be positive.")
    if config.link.outage_margin_db < 0.0:
        raise ValueError("Required operational margin cannot be negative.")

    legacy_rician = "rician" in jitter_model.lower()
    terminal_profiles_selected = (
        tx_jitter_profile is not None or rx_jitter_profile is not None
    )
    tx_jitter_profile = tx_jitter_profile or CONFIGURED_RANDOM
    rx_jitter_profile = rx_jitter_profile or CONFIGURED_RANDOM
    time_step_seconds = recommended_time_step(
        time_step_seconds, tx_jitter_profile, rx_jitter_profile
    )
    elapsed = _sample_times(duration_seconds, time_step_seconds)
    count = len(elapsed)
    transmitter, receiver = _terminals(config)
    wavelength = config.link.wavelength_m

    start_time = datetime.now(timezone.utc)
    plot_times = None
    time_axis_label = "Time (Seconds)"
    weather_kind = "none"
    weather_data = None
    if config.link.link_type == "inter-satellite":
        weather_description = "No atmospheric loss"
    elif not config.weather.use_live:
        weather_kind = "constant"
        weather_data = (
            config.weather.manual.visibility_km,
            config.weather.manual.attenuation_type,
        )
        weather_description = (
            f"Manual: {weather_data[0]:.2f} km, {weather_data[1]}"
        )
    elif config.weather.continuous_mode == "Current Hold":
        weather = fetch_current_weather(
            config.ground.latitude_deg, config.ground.longitude_deg
        )
        weather_kind = "constant"
        weather_data = (weather.visibility_km, weather.attenuation_type)
        plot_times = [start_time + timedelta(seconds=value) for value in elapsed]
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
        weather_kind = "history"
        weather_data = history
        start_time = history.times_utc[-1] - timedelta(seconds=duration_seconds)
        plot_times = [start_time + timedelta(seconds=value) for value in elapsed]
        time_axis_label = "Historical Time (UTC)"
        weather_description = (
            f"Past Replay: {len(history.times_utc)} samples ({history.source})"
        )

    if config.link.link_type == "inter-satellite":
        geometry_elapsed = [0.0, duration_seconds]
        geometry_ranges = [config.link.satellite_distance_km * 1000.0] * 2
        geometry_elevations = [math.nan, math.nan]
        geometry_visible = [True, True]
        trajectory_description = "Fixed inter-satellite range"
    else:
        geometry_step = config.orbit.geometry_sample_time_s
        if not math.isfinite(geometry_step) or geometry_step <= 0.0:
            raise ValueError("Orbit geometry sample time must be positive.")
        geometry_elapsed = _sample_times(duration_seconds, geometry_step)
        geometry = resolve_trajectory(config, geometry_elapsed, start_time)
        geometry_ranges = geometry.ranges_m
        geometry_elevations = geometry.elevations_deg
        geometry_visible = geometry.visible
        trajectory_description = geometry.source

    ranges_m = [
        _interpolate(geometry_elapsed, geometry_ranges, value) for value in elapsed
    ]
    if config.link.link_type == "inter-satellite":
        elevations: list[float | None] = [None] * count
        visible = [True] * count
    else:
        elevations = [
            _interpolate(geometry_elapsed, geometry_elevations, value)
            for value in elapsed
        ]
        visible = [
            value >= config.orbit.minimum_elevation_deg for value in elevations
        ]

    ideal_margins = [
        _ideal_margin(config, transmitter, receiver, distance)[0]
        for distance in ranges_m
    ]
    divergence = 1.22 * wavelength / transmitter.aperture_diameter_m
    generator = random.Random()
    tx_x, tx_y, tx_metadata = generate_terminal_jitter(
        tx_jitter_profile,
        transmitter.jitter_sigma_rad,
        time_step_seconds,
        count,
        generator,
    )
    rx_x, rx_y, rx_metadata = generate_terminal_jitter(
        rx_jitter_profile,
        receiver.jitter_sigma_rad,
        time_step_seconds,
        count,
        generator,
    )
    tx_suppression_db = config.link.tx_jitter_suppression_db
    rx_suppression_db = config.link.rx_jitter_suppression_db
    tx_scale = suppression_amplitude_scale(tx_suppression_db)
    rx_scale = suppression_amplitude_scale(rx_suppression_db)
    bias = (
        config.link.boresight_bias_rad
        if terminal_profiles_selected or legacy_rician
        else 0.0
    )
    tracking_losses = []
    for index, distance in enumerate(ranges_m):
        x_error = bias + tx_x[index] * tx_scale + rx_x[index] * rx_scale
        y_error = tx_y[index] * tx_scale + rx_y[index] * rx_scale
        beam_radius = distance * divergence
        displacement = distance * math.hypot(x_error, y_error)
        raw_loss = max(math.exp(-2.0 * displacement**2 / beam_radius**2), 1e-30)
        tracking_losses.append(10.0 * math.log10(raw_loss))

    if config.link.link_type == "inter-satellite":
        atmosphere_at_geometry = [0.0, 0.0]
    else:
        atmosphere_at_geometry = []
        for index, geometry_time in enumerate(geometry_elapsed):
            if not geometry_visible[index]:
                atmosphere_at_geometry.append(0.0)
                continue
            if weather_kind == "history":
                visibility_value = _interpolate(
                    weather_data.relative_seconds,
                    weather_data.visibility_km,
                    geometry_time,
                )
                nearest_index = min(
                    range(len(weather_data.relative_seconds)),
                    key=lambda item: abs(
                        weather_data.relative_seconds[item] - geometry_time
                    ),
                )
                attenuation_value = weather_data.attenuation_types[nearest_index]
            else:
                visibility_value, attenuation_value = weather_data
            atmosphere_at_geometry.append(
                atmospheric_loss_db(
                    visibility_value,
                    attenuation_value,
                    max(geometry_elevations[index], 0.001),
                    config.ground.height_km,
                    wavelength,
                    config.link.troposphere_height_km,
                    config.link.absorption_loss_db,
                )[0]
            )
    atmosphere_losses = [
        _interpolate(geometry_elapsed, atmosphere_at_geometry, value)
        for value in elapsed
    ]
    margins = [
        ideal - atmosphere + jitter
        for ideal, atmosphere, jitter in zip(
            ideal_margins, atmosphere_losses, tracking_losses
        )
    ]
    outage_margin = config.link.outage_margin_db
    service_outage = [
        not access or margin < outage_margin
        for access, margin in zip(visible, margins)
    ]
    outage_rate = 100.0 * sum(service_outage) / count
    no_access_rate = 100.0 * sum(not access for access in visible) / count
    visible_margins = [
        margin for margin, access in zip(margins, visible) if access
    ]
    visible_outage_rate = (
        100.0
        * sum(value < outage_margin for value in visible_margins)
        / len(visible_margins)
        if visible_margins
        else math.nan
    )

    return ContinuousResult(
        link_type=config.link.link_type,
        elapsed_seconds=elapsed,
        plot_times_utc=plot_times,
        time_axis_label=time_axis_label,
        margins_db=margins,
        ideal_margin_db=ideal_margins[0],
        ideal_margins_db=ideal_margins,
        outage_margin_db=outage_margin,
        outage_rate_pct=outage_rate,
        no_access_rate_pct=no_access_rate,
        visible_link_outage_rate_pct=visible_outage_rate,
        visible_mask=visible,
        ranges_km=[value / 1000.0 for value in ranges_m],
        elevations_deg=elevations,
        trajectory_description=trajectory_description,
        jitter_model=(
            f"Tx: {tx_metadata.display_name} ({tx_suppression_db:g} dB) | "
            f"Rx: {rx_metadata.display_name} ({rx_suppression_db:g} dB)"
        ),
        tx_jitter_profile=tx_metadata.name,
        rx_jitter_profile=rx_metadata.name,
        tx_jitter_suppression_db=tx_suppression_db,
        rx_jitter_suppression_db=rx_suppression_db,
        time_step_seconds=time_step_seconds,
        elevation_deg=elevations[0] if elevations else None,
        weather_description=weather_description,
    )


def format_snapshot(result: SnapshotResult) -> str:
    """Format snapshot output for the desktop application."""
    lines = [
        f"LINK BUDGET SNAPSHOT ({result.link_type.upper()})",
        "",
        f"Trajectory:               {result.trajectory_source}",
        f"Distance:                 {result.distance_km:.1f} km",
    ]
    if result.elevation_deg is not None:
        lines.append(f"Elevation:                {result.elevation_deg:.2f} deg")
    if result.azimuth_deg is not None and math.isfinite(result.azimuth_deg):
        lines.append(f"Azimuth:                  {result.azimuth_deg:.2f} deg")
    if not result.has_access:
        lines.extend(
            [
                f"Minimum elevation:        {result.minimum_elevation_deg:.2f} deg",
                "",
                "Status:                   NO ACCESS",
            ]
        )
        return "\n".join(lines)

    lines.extend(
        [
            f"Free-space path loss:     {result.path_loss_db:.2f} dB",
            f"Ideal reference margin:   {result.ideal_margin_db:.2f} dB",
        ]
    )
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
            f"Required operational:     {result.outage_margin_db:.2f} dB",
            f"Status:                   {'SUCCESS' if result.successful else 'FAILED / RISK'}",
        ]
    )
    return "\n".join(lines)

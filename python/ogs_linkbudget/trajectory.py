"""Two-body satellite trajectories and ground-relative geometry."""

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import math

from .config import SimulatorConfig
from .physics import EARTH_RADIUS_M, slant_range_circular_orbit

EARTH_MU_M3_S2 = 3.986004418e14
WGS84_FLATTENING = 1.0 / 298.257223563


@dataclass
class TrajectoryGeometry:
    """Satellite geometry sampled from the simulation start."""

    mode: str
    source: str
    times_utc: list[datetime]
    elapsed_seconds: list[float]
    positions_eci_m: list[tuple[float, float, float]]
    ranges_m: list[float]
    azimuths_deg: list[float]
    elevations_deg: list[float]
    visible: list[bool]


def resolve_trajectory(
    config: SimulatorConfig,
    elapsed_seconds: list[float],
    start_time_utc: datetime | None = None,
) -> TrajectoryGeometry:
    """Resolve fixed or propagated geometry relative to the ground station."""
    elapsed = [float(value) for value in elapsed_seconds]
    if (
        not elapsed
        or elapsed[0] != 0.0
        or any(not math.isfinite(value) or value < 0.0 for value in elapsed)
        or any(right < left for left, right in zip(elapsed, elapsed[1:]))
    ):
        raise ValueError(
            "Trajectory times must be finite, nonnegative, increasing, and start at zero."
        )
    minimum_elevation = config.orbit.minimum_elevation_deg
    if not math.isfinite(minimum_elevation) or not 0.0 <= minimum_elevation <= 90.0:
        raise ValueError("Minimum elevation must be from 0 to 90 degrees.")

    epoch = start_time_utc or datetime.now(timezone.utc)
    if epoch.tzinfo is None:
        epoch = epoch.replace(tzinfo=timezone.utc)
    else:
        epoch = epoch.astimezone(timezone.utc)
    times = [epoch + timedelta(seconds=value) for value in elapsed]
    mode = config.orbit.mode.lower()

    if mode == "fixed":
        elevation = config.orbit.worst_case_elevation_deg
        distance = slant_range_circular_orbit(
            elevation,
            config.satellite_a.height_km * 1000.0,
            config.ground.height_km * 1000.0,
        )
        positions = [(math.nan, math.nan, math.nan)] * len(elapsed)
        ranges = [distance] * len(elapsed)
        azimuths = [math.nan] * len(elapsed)
        elevations = [elevation] * len(elapsed)
        source = "Fixed worst-case geometry"
    elif mode == "keplerian":
        positions = _propagate_keplerian(config, elapsed)
        azimuths, elevations, ranges = _ground_relative_geometry(
            config, positions, times
        )
        source = "Two-body Keplerian elements"
    elif mode == "state-vector":
        positions = _propagate_state_vector(config, elapsed)
        azimuths, elevations, ranges = _ground_relative_geometry(
            config, positions, times
        )
        source = "Two-body ECI state vector"
    else:
        raise ValueError(f"Unsupported trajectory mode: {config.orbit.mode}")

    return TrajectoryGeometry(
        mode=mode,
        source=source,
        times_utc=times,
        elapsed_seconds=elapsed,
        positions_eci_m=positions,
        ranges_m=ranges,
        azimuths_deg=azimuths,
        elevations_deg=elevations,
        visible=[value >= minimum_elevation for value in elevations],
    )


def _propagate_keplerian(
    config: SimulatorConfig, elapsed: list[float]
) -> list[tuple[float, float, float]]:
    elements = config.orbit.keplerian
    semi_major_axis_m = elements.semi_major_axis_km * 1000.0
    eccentricity = elements.eccentricity
    if not math.isfinite(semi_major_axis_m) or semi_major_axis_m <= EARTH_RADIUS_M:
        raise ValueError("Semi-major axis must exceed the Earth equatorial radius.")
    if not math.isfinite(eccentricity) or not 0.0 <= eccentricity < 1.0:
        raise ValueError("Eccentricity must be in the range [0, 1).")
    if semi_major_axis_m * (1.0 - eccentricity) <= EARTH_RADIUS_M:
        raise ValueError("The configured Keplerian orbit intersects the Earth.")

    angles = (
        elements.inclination_deg,
        elements.raan_deg,
        elements.argument_of_periapsis_deg,
        elements.true_anomaly_deg,
    )
    if any(not math.isfinite(value) for value in angles):
        raise ValueError("Keplerian angular elements must be finite.")
    inclination, raan, argument, true_anomaly = map(math.radians, angles)
    eccentric_anomaly_0 = 2.0 * math.atan2(
        math.sqrt(1.0 - eccentricity) * math.sin(true_anomaly / 2.0),
        math.sqrt(1.0 + eccentricity) * math.cos(true_anomaly / 2.0),
    )
    mean_anomaly_0 = eccentric_anomaly_0 - eccentricity * math.sin(
        eccentric_anomaly_0
    )
    mean_motion = math.sqrt(EARTH_MU_M3_S2 / semi_major_axis_m**3)
    rotation = _matrix_multiply(
        _matrix_multiply(_rotation_z(raan), _rotation_x(inclination)),
        _rotation_z(argument),
    )

    positions = []
    for seconds_since_epoch in elapsed:
        mean_anomaly = mean_anomaly_0 + mean_motion * seconds_since_epoch
        eccentric_anomaly = mean_anomaly
        for _ in range(20):
            correction = (
                eccentric_anomaly
                - eccentricity * math.sin(eccentric_anomaly)
                - mean_anomaly
            ) / (1.0 - eccentricity * math.cos(eccentric_anomaly))
            eccentric_anomaly -= correction
            if abs(correction) < 1e-12:
                break
        perifocal = (
            semi_major_axis_m * (math.cos(eccentric_anomaly) - eccentricity),
            semi_major_axis_m
            * math.sqrt(1.0 - eccentricity**2)
            * math.sin(eccentric_anomaly),
            0.0,
        )
        positions.append(_matrix_vector(rotation, perifocal))
    return positions


def _propagate_state_vector(
    config: SimulatorConfig, elapsed: list[float]
) -> list[tuple[float, float, float]]:
    initial = config.orbit.state_vector
    if len(initial.position_eci_km) != 3 or len(initial.velocity_eci_km_s) != 3:
        raise ValueError("Initial ECI position and velocity must contain three values.")
    state = [
        *(float(value) * 1000.0 for value in initial.position_eci_km),
        *(float(value) * 1000.0 for value in initial.velocity_eci_km_s),
    ]
    if any(not math.isfinite(value) for value in state):
        raise ValueError("Initial ECI position and velocity must be finite.")
    if _norm(state[:3]) <= EARTH_RADIUS_M:
        raise ValueError("Initial ECI position must be above the Earth surface.")
    specific_energy = _dot(state[3:], state[3:]) / 2.0 - EARTH_MU_M3_S2 / _norm(
        state[:3]
    )
    if specific_energy >= 0.0:
        raise ValueError("Initial state must describe a bound elliptic orbit.")

    positions = [tuple(state[:3])]
    for left, right in zip(elapsed, elapsed[1:]):
        interval = right - left
        substep_count = max(1, math.ceil(interval))
        step = interval / substep_count
        for _ in range(substep_count):
            state = _rk4_step(state, step)
        if _norm(state[:3]) <= EARTH_RADIUS_M:
            raise ValueError("The propagated state-vector trajectory intersects Earth.")
        positions.append(tuple(state[:3]))
    return positions


def _rk4_step(state: list[float], step: float) -> list[float]:
    def derivative(value: list[float]) -> list[float]:
        radius = _norm(value[:3])
        acceleration_scale = -EARTH_MU_M3_S2 / radius**3
        return [
            value[3],
            value[4],
            value[5],
            acceleration_scale * value[0],
            acceleration_scale * value[1],
            acceleration_scale * value[2],
        ]

    k1 = derivative(state)
    k2 = derivative(_add_scaled(state, k1, step / 2.0))
    k3 = derivative(_add_scaled(state, k2, step / 2.0))
    k4 = derivative(_add_scaled(state, k3, step))
    return [
        value + step * (a + 2.0 * b + 2.0 * c + d) / 6.0
        for value, a, b, c, d in zip(state, k1, k2, k3, k4)
    ]


def _ground_relative_geometry(
    config: SimulatorConfig,
    positions_eci_m: list[tuple[float, float, float]],
    times_utc: list[datetime],
) -> tuple[list[float], list[float], list[float]]:
    station = _geodetic_to_ecef(
        config.ground.latitude_deg,
        config.ground.longitude_deg,
        config.ground.height_km * 1000.0,
    )
    latitude = math.radians(config.ground.latitude_deg)
    longitude = math.radians(config.ground.longitude_deg)
    azimuths = []
    elevations = []
    ranges = []
    for position_eci, time_utc in zip(positions_eci_m, times_utc):
        rotation = _greenwich_sidereal_angle(time_utc)
        cosine = math.cos(rotation)
        sine = math.sin(rotation)
        x, y, z = position_eci
        position_ecef = (cosine * x + sine * y, -sine * x + cosine * y, z)
        relative = tuple(value - origin for value, origin in zip(position_ecef, station))
        east = -math.sin(longitude) * relative[0] + math.cos(longitude) * relative[1]
        north = (
            -math.sin(latitude) * math.cos(longitude) * relative[0]
            - math.sin(latitude) * math.sin(longitude) * relative[1]
            + math.cos(latitude) * relative[2]
        )
        up = (
            math.cos(latitude) * math.cos(longitude) * relative[0]
            + math.cos(latitude) * math.sin(longitude) * relative[1]
            + math.sin(latitude) * relative[2]
        )
        horizontal = math.hypot(east, north)
        ranges.append(math.hypot(horizontal, up))
        azimuths.append(math.degrees(math.atan2(east, north)) % 360.0)
        elevations.append(math.degrees(math.atan2(up, horizontal)))
    return azimuths, elevations, ranges


def _greenwich_sidereal_angle(time_utc: datetime) -> float:
    julian_date = time_utc.timestamp() / 86400.0 + 2440587.5
    centuries = (julian_date - 2451545.0) / 36525.0
    gmst_deg = (
        280.46061837
        + 360.98564736629 * (julian_date - 2451545.0)
        + 0.000387933 * centuries**2
        - centuries**3 / 38710000.0
    )
    return math.radians(gmst_deg % 360.0)


def _geodetic_to_ecef(
    latitude_deg: float, longitude_deg: float, height_m: float
) -> tuple[float, float, float]:
    latitude = math.radians(latitude_deg)
    longitude = math.radians(longitude_deg)
    eccentricity_squared = WGS84_FLATTENING * (2.0 - WGS84_FLATTENING)
    prime_vertical_radius = EARTH_RADIUS_M / math.sqrt(
        1.0 - eccentricity_squared * math.sin(latitude) ** 2
    )
    return (
        (prime_vertical_radius + height_m)
        * math.cos(latitude)
        * math.cos(longitude),
        (prime_vertical_radius + height_m)
        * math.cos(latitude)
        * math.sin(longitude),
        (prime_vertical_radius * (1.0 - eccentricity_squared) + height_m)
        * math.sin(latitude),
    )


def _rotation_x(angle: float) -> tuple[tuple[float, ...], ...]:
    return (
        (1.0, 0.0, 0.0),
        (0.0, math.cos(angle), -math.sin(angle)),
        (0.0, math.sin(angle), math.cos(angle)),
    )


def _rotation_z(angle: float) -> tuple[tuple[float, ...], ...]:
    return (
        (math.cos(angle), -math.sin(angle), 0.0),
        (math.sin(angle), math.cos(angle), 0.0),
        (0.0, 0.0, 1.0),
    )


def _matrix_multiply(left, right) -> tuple[tuple[float, ...], ...]:
    return tuple(
        tuple(sum(left[row][index] * right[index][column] for index in range(3)) for column in range(3))
        for row in range(3)
    )


def _matrix_vector(matrix, vector) -> tuple[float, float, float]:
    return tuple(
        sum(matrix[row][column] * vector[column] for column in range(3))
        for row in range(3)
    )


def _norm(values) -> float:
    return math.sqrt(sum(value * value for value in values))


def _dot(left, right) -> float:
    return sum(a * b for a, b in zip(left, right))


def _add_scaled(values, derivative, scale: float) -> list[float]:
    return [value + scale * change for value, change in zip(values, derivative)]

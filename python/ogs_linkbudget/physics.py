"""Optical link geometry, gain, and atmospheric-loss equations."""

import math

EARTH_RADIUS_M = 6_378_137.0


def classify_attenuation(weather_code: float | int | None) -> str:
    """Map a WMO weather code to clear, rain, or snow attenuation."""
    if weather_code is None:
        return "clear"
    try:
        if math.isnan(float(weather_code)):
            return "clear"
    except (TypeError, ValueError):
        return "clear"

    code = round(float(weather_code))
    if code in {61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99}:
        return "rain"
    if code in {71, 73, 75, 77, 85, 86}:
        return "snow"
    return "clear"


def slant_range_circular_orbit(
    elevation_deg: float,
    satellite_height_m: float,
    ground_height_m: float,
) -> float:
    """Calculate line-of-sight range from a ground site to a circular orbit."""
    if not 0.0 < elevation_deg <= 90.0:
        raise ValueError("Elevation must be greater than 0 and at most 90 degrees.")
    ground_radius = EARTH_RADIUS_M + ground_height_m
    satellite_radius = EARTH_RADIUS_M + satellite_height_m
    if satellite_radius <= ground_radius:
        raise ValueError("Satellite altitude must exceed ground-station altitude.")

    elevation = math.radians(elevation_deg)
    under_root = satellite_radius**2 - (ground_radius * math.cos(elevation)) ** 2
    return -ground_radius * math.sin(elevation) + math.sqrt(under_root)


def free_space_path_loss_db(distance_m: float, wavelength_m: float) -> float:
    """Return positive-convention free-space path loss in decibels."""
    if distance_m <= 0.0 or wavelength_m <= 0.0:
        raise ValueError("Distance and wavelength must be positive.")
    return 20.0 * math.log10(4.0 * math.pi * distance_m / wavelength_m)


def aperture_gain_linear(diameter_m: float, wavelength_m: float) -> float:
    """Return the linear optical aperture gain."""
    if diameter_m <= 0.0 or wavelength_m <= 0.0:
        raise ValueError("Aperture diameter and wavelength must be positive.")
    return (math.pi * diameter_m / wavelength_m) ** 2


def aperture_gain_db(diameter_m: float, wavelength_m: float) -> float:
    return 10.0 * math.log10(aperture_gain_linear(diameter_m, wavelength_m))


def pointing_loss_db(gain_linear: float, pointing_error_rad: float) -> float:
    return 4.3429 * gain_linear * pointing_error_rad**2


def atmospheric_loss_db(
    visibility_km: float,
    attenuation_type: str,
    elevation_deg: float,
    ground_height_km: float,
    wavelength_m: float,
    troposphere_height_km: float,
    absorption_loss_db: float,
) -> tuple[float, float, float]:
    """Return total, geometrical, and Mie scattering loss in decibels."""
    if visibility_km <= 0.0:
        raise ValueError("Visibility must be positive.")
    if not 0.0 < elevation_deg <= 90.0:
        raise ValueError("Elevation must be greater than 0 and at most 90 degrees.")

    sin_elevation = math.sin(math.radians(elevation_deg))
    atmospheric_path_km = (troposphere_height_km - ground_height_km) / sin_elevation

    attenuation_type = attenuation_type.lower()
    if attenuation_type == "rain":
        geometric_coefficient = 2.8 / visibility_km
    elif attenuation_type == "snow":
        geometric_coefficient = 58.0 / visibility_km
    else:
        if visibility_km <= 0.5:
            delta = 0.0
        elif visibility_km <= 1.0:
            delta = visibility_km - 0.5
        elif visibility_km <= 6.0:
            delta = 0.16 * visibility_km + 0.34
        elif visibility_km <= 50.0:
            delta = 1.3
        else:
            delta = 1.6
        geometric_coefficient = (3.91 / visibility_km) * (
            (wavelength_m * 1e9 / 550.0) ** -delta
        )

    geometric_loss_db = 4.3429 * geometric_coefficient * atmospheric_path_km

    wavelength_um = wavelength_m * 1e6
    a = (
        0.000487 * wavelength_um**3
        - 0.002237 * wavelength_um**2
        + 0.003864 * wavelength_um
        - 0.004442
    )
    b = (
        -0.00573 * wavelength_um**3
        + 0.02639 * wavelength_um**2
        - 0.04552 * wavelength_um
        + 0.05164
    )
    c = (
        0.02565 * wavelength_um**3
        - 0.1191 * wavelength_um**2
        + 0.20385 * wavelength_um
        - 0.216
    )
    d = (
        -0.0638 * wavelength_um**3
        + 0.3034 * wavelength_um**2
        - 0.5083 * wavelength_um
        + 0.425
    )
    mie_extinction_ratio = (
        a * ground_height_km**3
        + b * ground_height_km**2
        + c * ground_height_km
        + d
    )
    mie_loss_db = 4.3429 * mie_extinction_ratio / sin_elevation
    total_loss_db = absorption_loss_db + geometric_loss_db + mie_loss_db
    return total_loss_db, geometric_loss_db, mie_loss_db

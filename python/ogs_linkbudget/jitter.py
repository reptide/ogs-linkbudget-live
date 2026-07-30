"""Terminal pointing-jitter profiles and time-series generation."""

from dataclasses import dataclass
import math
import random


CONFIGURED_RANDOM = "Configured Random"
OLYMPUS_FLIGHT_PSD = "OLYMPUS Platform PSD (Open Loop)"
OLYMPUS_AFTER_ATP = "OLYMPUS After ATP (Reference Design)"
MICIUS_BEFORE_ATP = "Micius Before ATP (Open Loop)"
MICIUS_AFTER_ATP = "Micius After ATP (Measured)"
JITTER_PROFILES = (
    CONFIGURED_RANDOM,
    OLYMPUS_FLIGHT_PSD,
    OLYMPUS_AFTER_ATP,
    MICIUS_BEFORE_ATP,
    MICIUS_AFTER_ATP,
)


def suppression_amplitude_scale(suppression_db: float) -> float:
    """Convert jitter suppression in dB to an angular-amplitude multiplier."""
    if suppression_db < 0.0:
        raise ValueError("Jitter suppression cannot be negative.")
    return 10.0 ** (-suppression_db / 20.0)


@dataclass(frozen=True)
class JitterMetadata:
    name: str
    display_name: str
    radial_rms_rad: float
    modeled_bandwidth_hz: float | None


def recommended_time_step(
    requested_seconds: float, tx_profile: str, rx_profile: str
) -> float:
    """Return a step that represents the selected profiles' frequency content."""
    if any("micius" in profile.lower() for profile in (tx_profile, rx_profile)):
        return min(requested_seconds, 0.004)
    if any("olympus" in profile.lower() for profile in (tx_profile, rx_profile)):
        return min(requested_seconds, 0.005)
    return requested_seconds


def _filtered_band_component(
    low_hz: float,
    high_hz: float,
    target_sigma_rad: float,
    time_step_seconds: float,
    sample_count: int,
    generator: random.Random,
) -> list[float]:
    """Generate one axis of a band-shaped component with the requested RMS."""
    high_decay = math.exp(-2.0 * math.pi * high_hz * time_step_seconds)
    if low_hz == 0.0:
        low_decay = None
        variance_factor = (1.0 - high_decay) / (1.0 + high_decay)
    else:
        low_decay = math.exp(-2.0 * math.pi * low_hz * time_step_seconds)
        variance_factor = (
            (1.0 - high_decay) ** 2 / (1.0 - high_decay**2)
            + (1.0 - low_decay) ** 2 / (1.0 - low_decay**2)
            - 2.0
            * (1.0 - high_decay)
            * (1.0 - low_decay)
            / (1.0 - high_decay * low_decay)
        )
    driving_sigma = target_sigma_rad / math.sqrt(variance_factor)
    high_state = 0.0
    low_state = 0.0
    burn_in = math.ceil(5.0 / time_step_seconds)
    values: list[float] = []
    for index in range(burn_in + sample_count):
        white_sample = generator.gauss(0.0, driving_sigma)
        high_state = (
            high_decay * high_state + (1.0 - high_decay) * white_sample
        )
        if low_decay is None:
            output = high_state
        else:
            low_state = (
                low_decay * low_state + (1.0 - low_decay) * white_sample
            )
            output = high_state - low_state
        if index >= burn_in:
            values.append(output)
    return values


def generate_terminal_jitter(
    profile: str,
    configured_sigma_rad: float,
    time_step_seconds: float,
    sample_count: int,
    generator: random.Random,
) -> tuple[list[float], list[float], JitterMetadata]:
    """Generate independent x/y angular motion for one terminal."""
    if sample_count < 1:
        raise ValueError("Jitter generation requires at least one sample.")
    if "olympus" in profile.lower():
        corner_frequency_hz = 1.0
        radial_psd_level_rad2_hz = 160e-12
        axis_variance = (
            radial_psd_level_rad2_hz * math.pi * corner_frequency_hz / 4.0
        )
        axis_sigma = math.sqrt(axis_variance)
        correlation = math.exp(
            -2.0 * math.pi * corner_frequency_hz * time_step_seconds
        )
        innovation_sigma = axis_sigma * math.sqrt(1.0 - correlation**2)

        x_error = [generator.gauss(0.0, axis_sigma)]
        y_error = [generator.gauss(0.0, axis_sigma)]
        for _ in range(1, sample_count):
            x_error.append(
                correlation * x_error[-1]
                + generator.gauss(0.0, innovation_sigma)
            )
            y_error.append(
                correlation * y_error[-1]
                + generator.gauss(0.0, innovation_sigma)
            )
        open_loop_radial_rms = math.sqrt(2.0 * axis_variance)
        if "after atp" in profile.lower():
            reference_residual_rms = 0.34e-6
            residual_scale = reference_residual_rms / open_loop_radial_rms
            x_error = [value * residual_scale for value in x_error]
            y_error = [value * residual_scale for value in y_error]
            metadata = JitterMetadata(
                name=OLYMPUS_AFTER_ATP,
                display_name="OLYMPUS After ATP (Reference)",
                radial_rms_rad=reference_residual_rms,
                modeled_bandwidth_hz=100.0,
            )
            return x_error, y_error, metadata
        metadata = JitterMetadata(
            name=OLYMPUS_FLIGHT_PSD,
            display_name="OLYMPUS Open Loop",
            radial_rms_rad=open_loop_radial_rms,
            modeled_bandwidth_hz=100.0,
        )
        return x_error, y_error, metadata
    if "micius" in profile.lower():
        if "after atp" in profile.lower():
            band_radial_rms_urad = (
                (0.0, 1.0, 0.16),
                (1.0, 10.0, 0.26),
                (10.0, 50.0, 0.25),
                (50.0, 100.0, 0.28),
            )
            metadata_name = MICIUS_AFTER_ATP
            display_name = "Micius After ATP"
        else:
            band_radial_rms_urad = (
                (0.0, 1.0, 8.6),
                (1.0, 10.0, 2.8),
                (10.0, 50.0, 1.9),
                (50.0, 100.0, 0.6),
            )
            metadata_name = MICIUS_BEFORE_ATP
            display_name = "Micius Before ATP"
        x_error = [0.0] * sample_count
        y_error = [0.0] * sample_count
        radial_variance = 0.0
        for low_hz, high_hz, radial_rms_urad in band_radial_rms_urad:
            radial_rms_rad = radial_rms_urad * 1e-6
            axis_sigma_rad = radial_rms_rad / math.sqrt(2.0)
            x_band = _filtered_band_component(
                low_hz,
                high_hz,
                axis_sigma_rad,
                time_step_seconds,
                sample_count,
                generator,
            )
            y_band = _filtered_band_component(
                low_hz,
                high_hz,
                axis_sigma_rad,
                time_step_seconds,
                sample_count,
                generator,
            )
            x_error = [
                total + component for total, component in zip(x_error, x_band)
            ]
            y_error = [
                total + component for total, component in zip(y_error, y_band)
            ]
            radial_variance += radial_rms_rad**2
        metadata = JitterMetadata(
            name=metadata_name,
            display_name=display_name,
            radial_rms_rad=math.sqrt(radial_variance),
            modeled_bandwidth_hz=100.0,
        )
        return x_error, y_error, metadata
    if profile.lower() != CONFIGURED_RANDOM.lower():
        raise ValueError(f"Unsupported jitter profile: {profile}")

    x_error = [
        generator.gauss(0.0, configured_sigma_rad) for _ in range(sample_count)
    ]
    y_error = [
        generator.gauss(0.0, configured_sigma_rad) for _ in range(sample_count)
    ]
    metadata = JitterMetadata(
        name=CONFIGURED_RANDOM,
        display_name=CONFIGURED_RANDOM,
        radial_rms_rad=math.sqrt(2.0) * configured_sigma_rad,
        modeled_bandwidth_hz=None,
    )
    return x_error, y_error, metadata

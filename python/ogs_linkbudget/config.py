"""Configuration models and defaults for the OGS simulator."""

from dataclasses import dataclass, field


@dataclass
class Terminal:
    optics_efficiency: float
    aperture_diameter_m: float
    pointing_error_rad: float
    jitter_sigma_rad: float
    height_km: float = 0.0


@dataclass
class GroundStation(Terminal):
    latitude_deg: float = 36.3504
    longitude_deg: float = 127.3845


@dataclass
class KeplerianConfig:
    semi_major_axis_km: float = 6928.137
    eccentricity: float = 0.001
    inclination_deg: float = 51.6
    raan_deg: float = 0.0
    argument_of_periapsis_deg: float = 0.0
    true_anomaly_deg: float = 0.0


@dataclass
class StateVectorConfig:
    position_eci_km: list[float] = field(
        default_factory=lambda: [6928.137, 0.0, 0.0]
    )
    velocity_eci_km_s: list[float] = field(
        default_factory=lambda: [0.0, 4.72, 5.93]
    )


@dataclass
class OrbitConfig:
    mode: str = "fixed"
    worst_case_elevation_deg: float = 20.0
    minimum_elevation_deg: float = 5.0
    geometry_sample_time_s: float = 1.0
    keplerian: KeplerianConfig = field(default_factory=KeplerianConfig)
    state_vector: StateVectorConfig = field(default_factory=StateVectorConfig)


@dataclass
class LinkConfig:
    wavelength_m: float = 1550e-9
    troposphere_height_km: float = 20.0
    satellite_distance_km: float = 1000.0
    link_type: str = "downlink"
    transmit_power_dbm: float = 17.5
    required_power_dbm: float = -35.5
    outage_margin_db: float = 3.0
    absorption_loss_db: float = 0.01
    boresight_bias_rad: float = 0.0
    tx_jitter_suppression_db: float = 0.0
    rx_jitter_suppression_db: float = 0.0


@dataclass
class ManualWeather:
    visibility_km: float = 10.0
    attenuation_type: str = "clear"


@dataclass
class WeatherConfig:
    use_live: bool = True
    continuous_mode: str = "Past Replay"
    manual: ManualWeather = field(default_factory=ManualWeather)


@dataclass
class SimulatorConfig:
    ground: GroundStation
    satellite_a: Terminal
    satellite_b: Terminal
    orbit: OrbitConfig = field(default_factory=OrbitConfig)
    link: LinkConfig = field(default_factory=LinkConfig)
    weather: WeatherConfig = field(default_factory=WeatherConfig)


def default_config() -> SimulatorConfig:
    """Return defaults equivalent to ogs_config.m."""
    ground = GroundStation(
        optics_efficiency=0.8,
        aperture_diameter_m=1.0,
        pointing_error_rad=1e-6,
        jitter_sigma_rad=1e-6,
        height_km=0.1,
    )
    satellite_a = Terminal(
        optics_efficiency=0.8,
        aperture_diameter_m=0.07,
        pointing_error_rad=1e-6,
        jitter_sigma_rad=2e-6,
        height_km=550.0,
    )
    satellite_b = Terminal(
        optics_efficiency=0.8,
        aperture_diameter_m=0.06,
        pointing_error_rad=1e-6,
        jitter_sigma_rad=2e-6,
    )
    return SimulatorConfig(ground=ground, satellite_a=satellite_a, satellite_b=satellite_b)

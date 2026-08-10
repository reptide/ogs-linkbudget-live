"""Tests for snapshot and continuous simulation behavior."""

from datetime import datetime, timedelta, timezone
import math
import random
import unittest
from unittest.mock import patch

from ogs_linkbudget.config import default_config
from ogs_linkbudget.jitter import (
    CONFIGURED_RANDOM,
    MICIUS_AFTER_ATP,
    MICIUS_BEFORE_ATP,
    OLYMPUS_AFTER_ATP,
    OLYMPUS_FLIGHT_PSD,
    generate_terminal_jitter,
    suppression_amplitude_scale,
)
from ogs_linkbudget.simulation import run_continuous, run_snapshot
from ogs_linkbudget.weather import CurrentWeather, WeatherHistory


class SimulationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = default_config()
        self.config.weather.use_live = False

    def test_all_link_directions_run(self) -> None:
        for link_type in ("downlink", "uplink", "inter-satellite"):
            with self.subTest(link_type=link_type):
                self.config.link.link_type = link_type
                result = run_snapshot(self.config)
                self.assertEqual(result.link_type, link_type)
                self.assertGreater(result.distance_km, 0.0)

    def test_moving_trajectory_updates_continuous_geometry(self) -> None:
        self.config.orbit.mode = "keplerian"
        self.config.orbit.minimum_elevation_deg = 0.0
        self.config.ground.latitude_deg = 0.0
        self.config.ground.longitude_deg = 30.0
        result = run_continuous(self.config, 60.0, 1.0)
        self.assertGreater(max(result.ranges_km) - min(result.ranges_km), 0.1)
        self.assertGreater(
            max(result.ideal_margins_db) - min(result.ideal_margins_db), 0.001
        )
        self.assertEqual(len(result.visible_mask), len(result.elapsed_seconds))

    def test_no_access_is_counted_as_service_outage(self) -> None:
        self.config.orbit.mode = "keplerian"
        self.config.orbit.minimum_elevation_deg = 90.0
        result = run_continuous(self.config, 1.0, 0.1)
        self.assertEqual(result.no_access_rate_pct, 100.0)
        self.assertEqual(result.outage_rate_pct, 100.0)

        snapshot = run_snapshot(self.config)
        self.assertFalse(snapshot.has_access)
        self.assertFalse(snapshot.successful)

    def test_operational_margin_defaults_to_three_db(self) -> None:
        snapshot = run_snapshot(self.config)
        continuous = run_continuous(self.config, 1.0, 0.1)
        self.assertEqual(snapshot.outage_margin_db, 3.0)
        self.assertEqual(continuous.outage_margin_db, 3.0)

    def test_snapshot_status_uses_configured_operational_margin(self) -> None:
        self.config.link.required_power_dbm = -100.0
        baseline = run_snapshot(self.config)
        self.config.link.outage_margin_db = baseline.margin_db + 0.1
        result = run_snapshot(self.config)
        self.assertFalse(result.successful)

        self.config.link.outage_margin_db = max(0.0, baseline.margin_db - 0.1)
        result = run_snapshot(self.config)
        self.assertTrue(result.successful)

    def test_continuous_outage_uses_configured_operational_margin(self) -> None:
        self.config.link.outage_margin_db = 1_000.0
        result = run_continuous(self.config, 1.0, 0.1)
        self.assertEqual(result.outage_rate_pct, 100.0)

        self.config.link.outage_margin_db = 0.0
        result = run_continuous(self.config, 1.0, 0.1)
        expected = (
            100.0
            * sum(value < 0.0 for value in result.margins_db)
            / len(result.margins_db)
        )
        self.assertEqual(result.outage_rate_pct, expected)

    def test_negative_operational_margin_is_rejected(self) -> None:
        self.config.link.outage_margin_db = -0.1
        with self.assertRaises(ValueError):
            run_snapshot(self.config)
        with self.assertRaises(ValueError):
            run_continuous(self.config, 1.0, 0.1)

    def test_continuous_sample_count_and_reference(self) -> None:
        result = run_continuous(self.config, 1.0, 0.1)
        self.assertEqual(len(result.elapsed_seconds), 11)
        self.assertEqual(len(result.margins_db), 11)
        self.assertTrue(all(value <= result.ideal_margin_db for value in result.margins_db))

    def test_each_run_uses_fresh_random_samples(self) -> None:
        first = run_continuous(self.config, 1.0, 0.1)
        second = run_continuous(self.config, 1.0, 0.1)
        self.assertNotEqual(first.margins_db, second.margins_db)

    def test_tx_and_rx_profiles_are_selected_independently(self) -> None:
        result = run_continuous(
            self.config,
            1.0,
            0.1,
            tx_jitter_profile=OLYMPUS_FLIGHT_PSD,
            rx_jitter_profile=CONFIGURED_RANDOM,
        )
        self.assertEqual(result.tx_jitter_profile, OLYMPUS_FLIGHT_PSD)
        self.assertEqual(result.rx_jitter_profile, CONFIGURED_RANDOM)
        self.assertEqual(result.time_step_seconds, 0.005)
        self.assertEqual(len(result.elapsed_seconds), 201)

    def test_olympus_profile_matches_reference_rms_and_is_correlated(self) -> None:
        x_error, y_error, metadata = generate_terminal_jitter(
            OLYMPUS_FLIGHT_PSD,
            configured_sigma_rad=1e-6,
            time_step_seconds=0.005,
            sample_count=100_000,
            generator=random.Random(42),
        )
        radial_mean_square = sum(
            x_value**2 + y_value**2
            for x_value, y_value in zip(x_error, y_error)
        ) / len(x_error)
        measured_rms = math.sqrt(radial_mean_square)
        self.assertAlmostEqual(
            measured_rms / metadata.radial_rms_rad,
            1.0,
            delta=0.04,
        )
        x_mean = sum(x_error) / len(x_error)
        lag_one = sum(
            (x_error[index] - x_mean) * (x_error[index - 1] - x_mean)
            for index in range(1, len(x_error))
        )
        variance = sum((value - x_mean) ** 2 for value in x_error)
        self.assertGreater(lag_one / variance, 0.9)

    def test_olympus_after_atp_matches_reference_design_residual(self) -> None:
        x_error, y_error, metadata = generate_terminal_jitter(
            OLYMPUS_AFTER_ATP,
            configured_sigma_rad=1e-6,
            time_step_seconds=0.005,
            sample_count=100_000,
            generator=random.Random(42),
        )
        radial_mean_square = sum(
            x_value**2 + y_value**2
            for x_value, y_value in zip(x_error, y_error)
        ) / len(x_error)
        measured_rms = math.sqrt(radial_mean_square)
        self.assertAlmostEqual(metadata.radial_rms_rad * 1e6, 0.34)
        self.assertAlmostEqual(
            measured_rms / metadata.radial_rms_rad,
            1.0,
            delta=0.04,
        )

    def test_micius_before_atp_matches_published_band_rms(self) -> None:
        x_error, y_error, metadata = generate_terminal_jitter(
            MICIUS_BEFORE_ATP,
            configured_sigma_rad=1e-6,
            time_step_seconds=0.004,
            sample_count=100_000,
            generator=random.Random(42),
        )
        radial_mean_square = sum(
            x_value**2 + y_value**2
            for x_value, y_value in zip(x_error, y_error)
        ) / len(x_error)
        measured_rms = math.sqrt(radial_mean_square)
        self.assertAlmostEqual(metadata.radial_rms_rad * 1e6, 9.26, delta=0.02)
        self.assertAlmostEqual(
            measured_rms / metadata.radial_rms_rad,
            1.0,
            delta=0.05,
        )

    def test_micius_after_atp_matches_published_band_rms(self) -> None:
        x_error, y_error, metadata = generate_terminal_jitter(
            MICIUS_AFTER_ATP,
            configured_sigma_rad=1e-6,
            time_step_seconds=0.004,
            sample_count=100_000,
            generator=random.Random(42),
        )
        radial_mean_square = sum(
            x_value**2 + y_value**2
            for x_value, y_value in zip(x_error, y_error)
        ) / len(x_error)
        measured_rms = math.sqrt(radial_mean_square)
        expected_rms_urad = math.sqrt(
            0.16**2 + 0.26**2 + 0.25**2 + 0.28**2
        )
        self.assertAlmostEqual(
            metadata.radial_rms_rad * 1e6,
            expected_rms_urad,
        )
        self.assertAlmostEqual(
            measured_rms / metadata.radial_rms_rad,
            1.0,
            delta=0.05,
        )

    def test_micius_selection_uses_250_hz_sampling(self) -> None:
        result = run_continuous(
            self.config,
            1.0,
            0.1,
            tx_jitter_profile=MICIUS_BEFORE_ATP,
            rx_jitter_profile=CONFIGURED_RANDOM,
        )
        self.assertEqual(result.tx_jitter_profile, MICIUS_BEFORE_ATP)
        self.assertEqual(result.time_step_seconds, 0.004)
        self.assertEqual(len(result.elapsed_seconds), 251)

    def test_suppression_db_scales_angular_amplitude(self) -> None:
        self.assertAlmostEqual(suppression_amplitude_scale(0.0), 1.0)
        self.assertAlmostEqual(suppression_amplitude_scale(20.0), 0.1)
        self.assertAlmostEqual(suppression_amplitude_scale(40.0), 0.01)
        with self.assertRaises(ValueError):
            suppression_amplitude_scale(-1.0)

    def test_tx_and_rx_suppression_are_reported_independently(self) -> None:
        self.config.link.tx_jitter_suppression_db = 20.0
        self.config.link.rx_jitter_suppression_db = 10.0
        result = run_continuous(
            self.config,
            1.0,
            0.1,
            tx_jitter_profile=MICIUS_BEFORE_ATP,
            rx_jitter_profile=OLYMPUS_FLIGHT_PSD,
        )
        self.assertEqual(result.tx_jitter_suppression_db, 20.0)
        self.assertEqual(result.rx_jitter_suppression_db, 10.0)
        self.assertIn("20 dB", result.jitter_model)
        self.assertIn("10 dB", result.jitter_model)

    @patch("ogs_linkbudget.simulation.fetch_current_weather")
    def test_current_hold_uses_one_weather_sample(self, fetch_current) -> None:
        fetch_current.return_value = CurrentWeather(
            visibility_km=20.0,
            attenuation_type="clear",
            weather_code=0.0,
            cloud_cover_pct=0.0,
            wind_speed_ms=0.0,
            temperature_c=20.0,
            time_utc=datetime.now(timezone.utc),
            source="test",
        )
        self.config.weather.use_live = True
        self.config.weather.continuous_mode = "Current Hold"
        result = run_continuous(self.config, 1.0, 0.1)
        fetch_current.assert_called_once()
        self.assertIsNotNone(result.plot_times_utc)

    @patch("ogs_linkbudget.simulation.fetch_weather_history")
    def test_past_replay_interpolates_history(self, fetch_history) -> None:
        end = datetime.now(timezone.utc)
        fetch_history.return_value = WeatherHistory(
            times_utc=[end - timedelta(seconds=60), end],
            relative_seconds=[0.0, 60.0],
            visibility_km=[10.0, 20.0],
            weather_codes=[0.0, 0.0],
            attenuation_types=["clear", "clear"],
            source="test",
        )
        self.config.weather.use_live = True
        self.config.weather.continuous_mode = "Past Replay"
        result = run_continuous(self.config, 60.0, 10.0)
        fetch_history.assert_called_once()
        self.assertEqual(len(result.margins_db), 7)
        self.assertIsNotNone(result.plot_times_utc)


if __name__ == "__main__":
    unittest.main()

"""Tests for snapshot and continuous simulation behavior."""

from datetime import datetime, timedelta, timezone
import unittest
from unittest.mock import patch

from ogs_linkbudget.config import default_config
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

    def test_continuous_sample_count_and_reference(self) -> None:
        result = run_continuous(self.config, 1.0, 0.1)
        self.assertEqual(len(result.elapsed_seconds), 11)
        self.assertEqual(len(result.margins_db), 11)
        self.assertTrue(all(value <= result.ideal_margin_db for value in result.margins_db))

    def test_each_run_uses_fresh_random_samples(self) -> None:
        first = run_continuous(self.config, 1.0, 0.1)
        second = run_continuous(self.config, 1.0, 0.1)
        self.assertNotEqual(first.margins_db, second.margins_db)

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

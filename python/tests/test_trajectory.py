"""Tests for fixed and two-body satellite trajectory generation."""

from datetime import datetime, timezone
import math
import unittest

from ogs_linkbudget.config import default_config
from ogs_linkbudget.trajectory import resolve_trajectory


class TrajectoryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = default_config()
        self.epoch = datetime(2026, 1, 1, tzinfo=timezone.utc)

    def test_fixed_geometry_remains_constant(self) -> None:
        geometry = resolve_trajectory(
            self.config, [0.0, 30.0, 60.0], self.epoch
        )
        self.assertEqual(geometry.elevations_deg, [20.0, 20.0, 20.0])
        self.assertEqual(geometry.ranges_m, [geometry.ranges_m[0]] * 3)
        self.assertTrue(all(geometry.visible))

    def test_keplerian_orbit_starts_at_configured_periapsis(self) -> None:
        self.config.orbit.mode = "keplerian"
        self.config.orbit.keplerian.semi_major_axis_km = 7000.0
        self.config.orbit.keplerian.eccentricity = 0.01
        self.config.orbit.keplerian.true_anomaly_deg = 0.0
        geometry = resolve_trajectory(
            self.config, [float(value) for value in range(0, 601, 60)], self.epoch
        )
        radii_km = [
            math.sqrt(sum(component**2 for component in position)) / 1000.0
            for position in geometry.positions_eci_m
        ]
        self.assertAlmostEqual(radii_km[0], 6930.0, places=8)
        self.assertGreater(radii_km[-1], radii_km[0])
        self.assertGreater(max(geometry.ranges_m) - min(geometry.ranges_m), 1000.0)

    def test_state_vector_preserves_circular_orbit_radius(self) -> None:
        self.config.orbit.mode = "state-vector"
        radius_km = 7000.0
        earth_mu_km = 398600.4418
        self.config.orbit.state_vector.position_eci_km = [radius_km, 0.0, 0.0]
        self.config.orbit.state_vector.velocity_eci_km_s = [
            0.0,
            math.sqrt(earth_mu_km / radius_km),
            0.0,
        ]
        geometry = resolve_trajectory(
            self.config, [float(value) for value in range(0, 601, 10)], self.epoch
        )
        radii_km = [
            math.sqrt(sum(component**2 for component in position)) / 1000.0
            for position in geometry.positions_eci_m
        ]
        self.assertLess(max(abs(value - radius_km) for value in radii_km), 1e-5)

    def test_rejects_earth_intersecting_orbit(self) -> None:
        self.config.orbit.mode = "keplerian"
        self.config.orbit.keplerian.semi_major_axis_km = 6500.0
        self.config.orbit.keplerian.eccentricity = 0.1
        with self.assertRaisesRegex(ValueError, "intersects the Earth"):
            resolve_trajectory(self.config, [0.0], self.epoch)


if __name__ == "__main__":
    unittest.main()

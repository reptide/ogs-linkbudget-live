"""Tests for geometry, weather classification, and optical equations."""

import math
import unittest

from ogs_linkbudget.physics import (
    aperture_gain_db,
    atmospheric_loss_db,
    classify_attenuation,
    free_space_path_loss_db,
    slant_range_circular_orbit,
)


class PhysicsTests(unittest.TestCase):
    def test_weather_codes_are_classified(self) -> None:
        self.assertEqual(classify_attenuation(0), "clear")
        self.assertEqual(classify_attenuation(63), "rain")
        self.assertEqual(classify_attenuation(75), "snow")
        self.assertEqual(classify_attenuation(math.nan), "clear")

    def test_slant_range_decreases_with_elevation(self) -> None:
        low = slant_range_circular_orbit(20.0, 550_000.0, 100.0)
        high = slant_range_circular_orbit(90.0, 550_000.0, 100.0)
        self.assertGreater(low, high)
        self.assertAlmostEqual(high, 549_900.0, places=5)

    def test_free_space_loss_and_gain_are_positive(self) -> None:
        self.assertGreater(free_space_path_loss_db(1_000_000.0, 1550e-9), 0.0)
        self.assertGreater(aperture_gain_db(0.3, 1550e-9), 0.0)

    def test_atmospheric_components_sum_to_total(self) -> None:
        total, geometric, mie = atmospheric_loss_db(
            10.0, "clear", 20.0, 0.1, 1550e-9, 20.0, 0.01
        )
        self.assertAlmostEqual(total, 0.01 + geometric + mie)
        self.assertGreater(total, 0.0)


if __name__ == "__main__":
    unittest.main()

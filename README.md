# Real-Time Weather-Linked Optical Link Budget (OGS)

An automated MATLAB script designed to compute Free-Space Optical (FSO) communication link budgets between Optical Ground Stations (OGS) and Satellites (LEO/GEO) using real-time atmospheric measurements.

Instead of relying on idealized static tables or manual weather parameter overrides, this project integrates live local atmospheric visibility data directly from the **Open-Meteo API** to perform highly realistic link evaluations on the fly.

## Features

- **Live Meteorological Integration:** Automatically pulls ambient parameters (visibility, cloud coverage, temperature, wind speed) based on the ground station's latitude/longitude coordinate setup.
- **Dynamic Weather Classification:** Converts standard WMO (World Meteorological Organization) weather codes into exact geometric attenuation models (`rain`, `snow`, or `clear`).
- **MathWorks Compatible Core:** Standardizes data parameters (`gs`, `satA`, `satB`, `link`) to be fully backwards-compatible with the verified formulas found in MathWorks' *Optical Satellite Communication Link Budget Analysis* toolset.
- **Fault-Tolerant Engine:** Includes fallback default exceptions (e.g., standard 10 km visibility model under clear skies) so that field track simulations do not experience execution crashes if the tracking network drops.

## File Breakdown

- `run_link_budget_live.m`: Main execution script that queries data, performs link margin math, and outputs results.
- `ogs_config.m`: The centralized configuration panel. Adjust telescope dimensions, pointing tolerances, frequencies, target altitude, or geographic locations here.
- `fetch_live_weather.m`: Manages REST API interaction via `webread` with the Open-Meteo endpoint.
- `classify_attenuation.m`: Parses API response weather statuses into granular scattering definitions.

## Requirements

To run this simulation framework, you need:
- **MATLAB** (R2021a or newer recommended)
- **Satellite Communications Toolbox** (for native `fspl` and `slantRangeCircularOrbit` modules)
- Active internet connectivity (for real-time tracking mode)

## Quick Start

1. Clone or download this repository onto your workstation.
2. Open `ogs_config.m` to alter the target latitude, longitude, optical efficiency, or link direction types (`downlink`, `uplink`, `inter-satellite`).
3. Run the master script from the MATLAB Command Window:
   ```matlab
   run_link_budget_live
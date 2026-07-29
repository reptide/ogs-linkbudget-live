# Optical Ground Station Live Link Budget Simulator

A MATLAB and standard-library Python dashboard for evaluating free-space optical links between an optical ground station and a satellite, or between two satellites. Both applications combine link geometry, telescope gains, pointing behavior, atmospheric attenuation, and receiver sensitivity to estimate link margin and outage performance.

## Choose an application

The repository contains two parallel implementations:

| Application | Requirements | Start command |
|---|---|---|
| MATLAB | MATLAB with `uifigure` and Satellite Communications Toolbox | `ogs_gui` |
| Python | Python 3.10+ with Tkinter; no third-party packages | `python3 python/run.py` |

Open-Meteo supplies live and historical weather data to both applications and does not require an API key. Internet access is only required when **Live API** weather is selected.

Users without MATLAB can download the repository ZIP, extract it, open a terminal in the extracted folder, and run the Python command above. On Windows, `py python\run.py` can be used when `python3` is unavailable. See [python/README.md](python/README.md) for Python-specific instructions and tests.

### Python interface

<p align="center">
  <img src="images/python/python_gui_panel1.png" width="450" alt="Python Scenario Settings tab">
  <br>
  <em>Python scenario and continuous-simulation controls.</em>
</p>

<p align="center">
  <img src="images/python/python_simulation_result.png" width="650" alt="Python continuous simulation analytics">
  <br>
  <em>Python continuous link-margin, reference, distribution, and outage views.</em>
</p>

## Start the MATLAB simulator

Open the MATLAB project or add this folder to the MATLAB path, then run:

```matlab
ogs_gui
```

The GUI creates a configuration from the selected controls and dispatches either the snapshot or continuous simulation engine.

The engines can also be called directly:

```matlab
cfg = ogs_config();

run_link_budget_live(cfg);
run_link_budget_continuous(cfg, 60, 0.1, "Rayleigh (No Bias)");
```

The continuous function arguments are duration in seconds, sample interval in seconds, and jitter model. The GUI presents duration in minutes and converts it to seconds.

## Link directions

| Direction | Transmitter | Receiver | Distance and propagation |
|---|---|---|---|
| Downlink | Satellite A | Ground station | LEO slant range plus atmospheric loss |
| Uplink | Ground station | Satellite A | LEO slant range plus atmospheric loss |
| Inter-satellite | Satellite A | Satellite B | Configured satellite distance with no atmospheric loss |

The GUI’s Tx and Rx aperture controls follow these transmitter and receiver roles. For inter-satellite simulations, the two jitter controls represent Satellite A and Satellite B.

## Scenario Settings

The Scenario Settings tab defines geometry, weather, location, and simulation behavior.

1. **Link Direction** selects downlink, uplink, or inter-satellite operation.
2. **Worst-case Elevation** is the single conservative elevation used for ground-space calculations. Snapshot and continuous modes evaluate the link at this angle. Inter-satellite links do not use elevation.
3. **Atmosphere Data** selects:
   - **Live API**, which uses Open-Meteo data for the entered ground-station coordinates.
   - **Manual**, which uses `cfg.weather.Manual.VisibilityKm` and `cfg.weather.Manual.AttenuationType`.
4. **Station Latitude, Longitude, and Altitude** define the ground-station location. GUI altitude is entered in metres and stored in kilometres.
5. **Simulation Mode** selects:
   - **Single Snapshot**
   - **Continuous Tracking**
6. **Continuous Simulation Sub-settings** define:
   - Live weather timeline mode
   - Rayleigh or Rician pointing jitter
   - Duration from 1 to 60 minutes

<p align="center">
  <img src="images/gui_panel1.png" width="550" alt="Scenario Settings tab">
  <br>
  <em>Figure 1: MATLAB scenario and continuous-simulation controls.</em>
</p>

## Live weather timeline modes

The weather timeline selection applies to continuous ground-space simulations using Live API weather.

### Past Replay

Past Replay retrieves the weather window ending at the latest available Open-Meteo 15-minute timestep. A 60-minute run requests five samples:

```text
-60 min  -45 min  -30 min  -15 min  latest
```

Atmospheric loss is calculated at every weather sample and linearly interpolated onto the continuous signal timeline. The graph uses historical UTC timestamps.

### Current Hold

Current Hold retrieves one current-weather sample and assumes the resulting atmospheric loss remains constant for the selected future duration. Pointing jitter continues to vary throughout the run. The graph uses projected UTC timestamps.

Manual weather is constant for the complete run. Inter-satellite links bypass weather processing.

If an Open-Meteo request fails, the weather functions issue a warning and use clear conditions with 10 km visibility.

## Hardware Configuration

The Hardware Configuration tab controls the optical terminals and pointing model.

1. **Tx Laser Power** is entered in watts and converted to dBm.
2. **Wavelength** is entered in nanometres and converted to metres.
3. **Tx and Rx Aperture Diameters** determine transmitter divergence and terminal gains.
4. **Terminal Jitter** supplies one-sigma angular jitter in microradians:
   - Ground-space: satellite and ground-station jitter
   - Inter-satellite: Satellite A and Satellite B jitter
5. **Boresight Bias** supplies the constant angular offset used by the Rician model.

<p align="center">
  <img src="images/gui_panel2.png" width="550" alt="Hardware Configuration tab">
  <br>
  <em>Figure 2: MATLAB optical hardware and pointing controls.</em>
</p>

## Single Snapshot

The snapshot engine evaluates one deterministic link condition.

For ground-space links it:

1. Resolves current or manual weather.
2. Calculates slant range at the worst-case elevation.
3. Selects transmitter and receiver roles.
4. Calculates telescope gains and static pointing losses.
5. Calculates free-space and atmospheric losses.
6. Prints the resulting margin and success status in the MATLAB Command Window.

Inter-satellite snapshots use `cfg.link.SatDistance` and omit atmospheric loss.

## Continuous Tracking

The continuous engine combines a static link baseline with time-varying pointing loss.

### Pointing models

- **Rayleigh (No Bias):** two zero-mean Gaussian angular components produce radial pointing error.
- **Rician (With Bias):** the x-axis component includes `cfg.link.BoresightBias`.

Transmitter and receiver jitter combine as:

```text
sigma_total = sqrt(sigma_tx^2 + sigma_rx^2)
```

The radial angular error is converted to displacement at the receiver and applied to a diffraction-limited Gaussian beam.

### Random sampling

Each run initializes an internal shuffled random stream, so repeated simulations generate different pointing-jitter profiles. The simulator restores MATLAB’s caller random-generator state when the run finishes.

## Link-budget model

The terminal aperture gain is:

```text
G = 10 log10((pi D / lambda)^2)
```

The received-power baseline combines:

```text
Tx power
+ transmitter and receiver optical efficiency
+ transmitter and receiver aperture gain
- free-space path loss
- atmospheric loss
```

Link margin is received power minus `cfg.link.Preq`. A margin below `0 dB` is counted as an outage.

### Atmospheric attenuation

Ground-space atmospheric loss combines:

- Constant molecular absorption
- Visibility-based geometrical scattering
  - Rain coefficient
  - Snow coefficient
  - Generalized Kim model for clear, cloudy, fog, haze, and other visibility-driven conditions
- Mie scattering based on wavelength, station altitude, and elevation

Open-Meteo WMO weather codes are classified as `clear`, `rain`, or `snow` before selecting the geometrical-scattering model.

## Continuous results

<p align="center">
  <img src="images/simulation_result.png" width="600" alt="Continuous simulation analytics">
  <br>
  <em>Figure 3: MATLAB continuous link-margin and outage analytics.</em>
</p>

The analytics figure contains three views:

### Dynamic Margin Profile

The top plot shows link margin over the selected timeline. The red dashed line marks the `0 dB` outage threshold.

- Above `0 dB`: received power exceeds the required sensitivity.
- Below `0 dB`: the sample is in outage.

The green dash-dot reference line shows the margin for the same geometry and hardware with atmospheric and jitter losses removed. For inter-satellite links, which do not use atmospheric loss, the reference removes jitter loss only. The gap between the reference and the simulated profile shows the combined margin reduction from those disturbances.

For Past Replay and Current Hold, the horizontal axis contains UTC timestamps. Manual-weather and inter-satellite runs use elapsed seconds.

### Margin Probability Density

The lower-left histogram shows the distribution of margin samples. A wider distribution indicates greater pointing-loss variation. Boresight bias generally shifts the distribution toward lower margins.

### Outage Rate

The lower-right chart reports the percentage of timeline samples with margin below `0 dB`.

## Configuration structure

`ogs_config.m` returns the shared configuration used by the GUI and both engines.

| Structure | Purpose |
|---|---|
| `cfg.gs` | Ground-station coordinates, altitude, optics, pointing error, and jitter |
| `cfg.satA` | Primary satellite altitude, optics, pointing error, and jitter |
| `cfg.satB` | Inter-satellite receiver optics, pointing error, and jitter |
| `cfg.orbit` | Worst-case elevation and reserved TLE fields |
| `cfg.link` | Direction, wavelength, power, sensitivity, distance, absorption, and bias |
| `cfg.weather` | Live/manual selection, continuous timeline mode, and manual weather |

Important unit conventions:

| Field | Unit |
|---|---|
| `cfg.gs.Height` | km |
| `cfg.satA.Height` | km |
| `cfg.link.SatDistance` | km |
| `cfg.link.Wavelength` | m |
| `cfg.link.Ptx` | dBm |
| `cfg.link.Preq` | dBm |
| Pointing error, jitter, and bias fields | rad |

## Source files

| File | Responsibility |
|---|---|
| `ogs_gui.m` | Builds the GUI, maps controls to configuration, and launches simulations |
| `ogs_config.m` | Defines default ground station, satellites, link, orbit, and weather settings |
| `run_link_budget_live.m` | Computes and prints a single link-budget snapshot |
| `run_link_budget_continuous.m` | Generates randomized pointing-error timelines, margin plots, and outage statistics |
| `fetch_live_weather.m` | Retrieves the latest Open-Meteo conditions |
| `fetch_weather_history.m` | Retrieves the recent 15-minute weather window |
| `classify_attenuation.m` | Maps WMO weather codes to clear, rain, or snow attenuation |
| `compute_atmospheric_loss.m` | Calculates shared geometrical, Mie, and absorption losses |
| `python/run.py` | Launches the Python desktop application |
| `python/ogs_linkbudget/` | Contains the Python configuration, physics, weather, simulation, GUI, and chart modules |
| `python/tests/` | Verifies the Python geometry and simulation behavior without network access |

## Model scope

- Ground-space geometry uses one user-selected worst-case elevation for the complete calculation.
- TLE-based time-varying elevation is not implemented.
- Satellite A uses a configured circular-orbit altitude.
- Inter-satellite range is a fixed configured distance.
- Open-Meteo supplies model data rather than direct measurements from a dedicated station at the entered coordinates.
- Historical weather replay uses 15-minute samples and interpolates atmospheric loss across the signal timeline.
- Current Hold assumes weather remains unchanged for the selected future duration.
- The continuous engine models pointing jitter statistically; it does not model satellite attitude-control dynamics or temporal jitter correlation.

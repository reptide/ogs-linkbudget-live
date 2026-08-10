# Optical Ground Station Live Link Budget Simulator

A MATLAB and standard-library Python dashboard for evaluating free-space optical links between an optical ground station and a satellite, or between two satellites. Both applications combine link geometry, telescope gains, pointing behavior, atmospheric attenuation, and receiver sensitivity to estimate link margin and outage performance.

## Choose an application

The repository contains two parallel implementations:

| Application | Requirements | Start command |
|---|---|---|
| MATLAB | MATLAB with `uifigure` and Satellite Communications Toolbox; fixed or propagated trajectories | `ogs_gui` |
| Python | Python 3.10+ with Tkinter; no third-party packages; fixed or propagated trajectories | `python3 python/run.py` |

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
run_link_budget_continuous( ...
    cfg, 60, 0.1, ...
    "Micius Before ATP (Open Loop)", ...
    "Configured Random");
```

The continuous arguments are duration in seconds, requested sample interval, transmitter jitter profile, and receiver jitter profile. The GUI presents duration in minutes and converts it to seconds. OLYMPUS profiles use a maximum interval of `0.005 s` (200 Hz); Micius profiles use `0.004 s` (250 Hz) to represent their published content through 100 Hz.

## Link directions

| Direction | Transmitter | Receiver | Distance and propagation |
|---|---|---|---|
| Downlink | Satellite A | Ground station | Fixed or propagated slant range plus atmospheric loss |
| Uplink | Ground station | Satellite A | Fixed or propagated slant range plus atmospheric loss |
| Inter-satellite | Satellite A | Satellite B | Configured satellite distance with no atmospheric loss |

The GUI’s Tx and Rx aperture controls follow these transmitter and receiver roles. For inter-satellite simulations, the two jitter controls represent Satellite A and Satellite B.

## Scenario Settings

The Scenario Settings tab defines geometry, weather, location, and simulation behavior.

1. **Link Direction** selects downlink, uplink, or inter-satellite operation.
2. **Worst-case Elevation** is the conservative ground-space angle used by Fixed Worst-case Geometry. Propagated trajectories calculate elevation from the satellite state and ground-station position. Inter-satellite links do not use elevation.
3. **Atmosphere Data** selects:
   - **Live API**, which uses Open-Meteo data for the entered ground-station coordinates.
   - **Manual**, which uses `cfg.weather.Manual.VisibilityKm` and `cfg.weather.Manual.AttenuationType`.
4. **Station Latitude, Longitude, and Altitude** define the ground-station location. GUI altitude is entered in metres and stored in kilometres.
5. **Simulation Mode** selects:
   - **Single Snapshot**
   - **Continuous Tracking**
6. **Continuous Simulation Sub-settings** define:
   - Live weather timeline mode
   - Duration from 1 to 60 minutes

<p align="center">
  <img src="images/gui_panel1.png" width="550" alt="Scenario Settings tab">
  <br>
  <em>Figure 1: MATLAB scenario and continuous-simulation controls.</em>
</p>

## Trajectory

The MATLAB and Python Trajectory tabs select how Satellite A moves for ground-space links:

1. **Fixed Worst-case Geometry** preserves the simple design case. Satellite altitude and the Scenario tab's worst-case elevation determine one constant slant range.
2. **Keplerian Elements** accepts semi-major axis, eccentricity, inclination, right ascension of the ascending node (RAAN), argument of periapsis, and true anomaly at the simulation start.
3. **Initial State Vector** accepts the satellite's Earth-centered inertial (ECI) position in kilometres and velocity in kilometres per second at the simulation start. The origin is Earth's center of mass, not the ground station. The six inputs are `[X, Y, Z]` and `[Vx, Vy, Vz]` on inertial axes.

The two moving modes use an unperturbed two-body Earth model. Keplerian elements are propagated analytically, while the ECI state vector is integrated with fourth-order Runge-Kutta steps no longer than one second. The inertial position is rotated into the Earth-fixed frame for the run epoch and converted to azimuth, elevation, and slant range relative to the configured ground station.

For example, `[7000, 0, 0] km` with approximately `[0, 7.546, 0] km/s` describes a near-circular equatorial orbit. It does not describe a satellite located 7,000 km from the ground station.

**Minimum Elevation** is the ground-station access mask. Samples below it are unavailable rather than low-margin link samples. Continuous simulations sample trajectory geometry at `cfg.orbit.GeometrySampleTime`, which defaults to one second, and interpolate it onto the higher-rate pointing-jitter timeline.

## Live weather timeline modes

The weather timeline selection applies to continuous ground-space simulations using Live API weather.

### Past Replay

Past Replay retrieves the weather window ending at the latest available Open-Meteo 15-minute timestep. A 60-minute run requests five samples:

```text
-60 min  -45 min  -30 min  -15 min  latest
```

Weather is interpolated onto the trajectory timeline. Atmospheric loss is then recalculated at each trajectory sample using the satellite's current elevation and interpolated onto the continuous signal timeline. The graph uses historical UTC timestamps.

### Current Hold

Current Hold retrieves one current-weather sample and assumes the resulting atmospheric loss remains constant for the selected future duration. Pointing jitter continues to vary throughout the run. The graph uses projected UTC timestamps.

Manual weather is constant for the complete run. Inter-satellite links bypass weather processing.

If an Open-Meteo request fails, the weather functions issue a warning and use clear conditions with 10 km visibility.

## Hardware Configuration

The Hardware Configuration tab controls the optical terminals and pointing model.

1. **Tx Laser Power** is entered in watts and converted to dBm.
2. **Wavelength** is entered in nanometres and converted to metres.
3. **Tx and Rx Aperture Diameters** determine transmitter divergence and terminal gains.
4. **Terminal Jitter** supplies the per-axis one-sigma angular jitter used when that terminal selects **Configured Random**:
   - Ground-space: satellite and ground-station jitter
   - Inter-satellite: Satellite A and Satellite B jitter
5. **Boresight Bias** supplies a constant relative angular offset for continuous simulations.
6. **Required Operational Margin** defines the reserve above receiver sensitivity required for a successful link. It defaults to `3 dB` and can be configured from `0` to `30 dB`.

<p align="center">
  <img src="images/gui_panel2.png" width="550" alt="Hardware Configuration tab">
  <br>
  <em>Figure 2: MATLAB optical hardware and pointing controls.</em>
</p>

## Jitter Models

The Jitter Models tab groups the continuous pointing-disturbance controls:

1. **Tx Jitter Profile** independently selects Configured Random, an OLYMPUS open-loop or after-ATP reference, or a Micius before- or after-ATP measurement for the transmitter.
2. **Rx Jitter Profile** selects the receiver model independently.
3. **Additional Tx and Rx Suppression** attenuate the selected profiles from `0` to `60 dB`.

These controls are enabled only in Continuous Tracking mode. Configured Random uses the terminal amplitudes entered under Hardware Configuration; OLYMPUS and Micius use their model-defined motion levels. An after-ATP profile already includes tracking residual, so leave its additional suppression at `0 dB` to reproduce the reference profile alone.

## Single Snapshot

The snapshot engine evaluates one deterministic link condition.

For ground-space links it:

1. Resolves current or manual weather.
2. Resolves fixed or propagated trajectory geometry at the current epoch.
3. Selects transmitter and receiver roles.
4. Calculates telescope gains and static pointing losses.
5. Calculates free-space and atmospheric losses.
6. Prints the resulting margin and success status in the MATLAB Command Window. A propagated satellite below the elevation mask reports **NO ACCESS**.

Inter-satellite snapshots use `cfg.link.SatDistance` and omit atmospheric loss.

## Continuous Tracking

The continuous engine combines time-varying geometry, atmospheric attenuation, and pointing loss. Fixed mode retains a constant geometry baseline; moving modes update range and elevation throughout the run.

### Terminal jitter profiles

- **Configured Random:** each terminal generates independent zero-mean Gaussian x/y samples using its entered per-axis jitter.
- **OLYMPUS Platform PSD (Open Loop):** each terminal generates correlated x/y motion from the flight-derived one-sided radial spectrum `S(f) = 160/(1 + f²) µrad²/Hz`. Its power is divided equally across the axes, giving approximately `15.85 µrad` total radial RMS before suppression.
- **OLYMPUS After ATP (Reference Design):** scales the OLYMPUS-shaped disturbance to the `0.34 µrad` residual tracking-error target published for an optical-terminal design driven by OLYMPUS-equivalent spacecraft vibration. This is a design reference, not a measured OLYMPUS closed-loop flight spectrum; the source does not provide enough frequency-resolved residual data to reconstruct that spectrum.
- **Micius Before ATP (Open Loop):** a filter bank reproduces the published pre-suppression radial RMS values of `8.6`, `2.8`, `1.9`, and `0.6 µrad` in the `0–1`, `1–10`, `10–50`, and `50–100 Hz` bands. Their combined RMS is approximately `9.26 µrad`, consistent with the reported `9.3 µrad` full-band value.
- **Micius After ATP (Measured):** uses the measured residual band RMS values of `0.16`, `0.26`, `0.25`, and `0.28 µrad`. Their quadrature sum is approximately `0.48 µrad`, consistent with the paper’s rounded `0.47 µrad` full-band result.

The transmitter and receiver produce separate angular histories. Their relative error is:

```text
x_relative(t) = boresight_bias + x_tx(t) + x_rx(t)
y_relative(t) = y_tx(t) + y_rx(t)
```

This permits combinations such as an OLYMPUS transmitter with a configured-random receiver. The radial angular error is converted to displacement at the receiver and applied to a diffraction-limited Gaussian beam.

### ATP residual profiles and manual suppression

An ATP profile represents the angular error remaining after an acquisition, tracking, and pointing control system has responded. Real ATP rejection depends on disturbance frequency, control bandwidth, sensors, steering hardware, delay, and measurement noise. The measured Micius before/after bands therefore show different rejection in different parts of the spectrum.

The manual suppression fields are a simpler engineering control. They apply one constant amplitude factor to every frequency in the selected history:

```text
suppressed_angle = open_loop_angle * 10^(-suppression_dB/20)
suppressed_PSD   = open_loop_PSD   * 10^(-suppression_dB/10)
```

`0 dB` preserves the complete selected profile, `10 dB` produces `0.316×` angular RMS, `20 dB` produces `0.1×`, and `40 dB` produces `0.01×`. With an open-loop profile, this approximates a hypothetical uniform suppression system. With an after-ATP profile, a nonzero value represents hypothetical **additional** isolation or control after the published residual and compounds with it.

In this simplified model, the OLYMPUS reference residual is equivalent to applying approximately `33.4 dB` of uniform amplitude suppression to the modeled open-loop OLYMPUS history because only an integrated residual target is available. The Micius after-ATP option is different: it uses measured residuals in four frequency bands, so it changes the spectral distribution and cannot be reproduced exactly by one manual suppression value.

OLYMPUS supplies a conservative GEO platform reference, while Micius supplies LEO lasercom measurements before and after its ATP system. This comparison includes differences in spacecraft design and measurement conditions, so it is not a controlled GEO-versus-LEO experiment.

Sources: [JPL OLYMPUS flight transceiver reference](https://descanso.jpl.nasa.gov/monograph/series7/Descanso%207_chap05.pdf), [NASA/JPL optical-terminal reference design](https://ntrs.nasa.gov/citations/20060029570), [published OLYMPUS analytic parameters](https://xuebao.sjtu.edu.cn/article/2024/1006-2467/1006-2467-58-4-449.shtml), and the [Micius in-orbit angular micro-vibration measurements](https://opg.optica.org/ao/abstract.cfm?uri=ao-60-7-1881).

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

Link margin is received power minus `cfg.link.Preq`. The `0 dB` level is therefore the receiver-sensitivity boundary. A sample is counted as an operational outage when its margin falls below `cfg.link.OutageMarginDB`, which defaults to `3 dB`.

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

The top plot shows link margin over the selected timeline. The red dashed line marks the user-configured operational outage threshold, which defaults to `3 dB`. A gray dotted line retains the underlying `0 dB` receiver-sensitivity boundary.

- At or above the operational threshold: the configured reserve is satisfied.
- Between `0 dB` and the operational threshold: the receiver sensitivity is met, but the desired reserve is not.
- Below `0 dB`: received power is below the assumed receiver sensitivity.

The green dash-dot reference curve shows the margin for the same time-varying geometry and hardware with atmospheric and jitter losses removed. For inter-satellite links, which do not use atmospheric loss, the reference removes jitter loss only. The gap between the reference and the simulated profile shows the combined margin reduction from those disturbances. Ground-space plots contain gaps while a propagated satellite is below the elevation mask.

For Past Replay and Current Hold, the horizontal axis contains UTC timestamps. Manual-weather and inter-satellite runs use elapsed seconds.

### Margin Probability Density

The lower-left histogram shows the distribution of margin samples while the satellite is above the elevation mask. A wider distribution indicates greater pointing-loss variation. Boresight bias generally shifts the distribution toward lower margins.

### Outage Rate

The lower-right chart separates **Service Outage**, which includes unavailable geometry and visible samples below the operational margin, from **No Access**, which is caused only by the elevation mask. Its title also reports the conditional outage percentage among visible samples.

## Configuration structure

`ogs_config.m` returns the shared configuration used by the GUI and both engines.

| Structure | Purpose |
|---|---|
| `cfg.gs` | Ground-station coordinates, altitude, optics, pointing error, and jitter |
| `cfg.satA` | Primary satellite altitude, optics, pointing error, and jitter |
| `cfg.satB` | Inter-satellite receiver optics, pointing error, and jitter |
| `cfg.orbit` | Trajectory mode, fixed geometry, elevation mask, Keplerian elements, and initial ECI state vector |
| `cfg.link` | Direction, wavelength, power, sensitivity, operational margin, distance, absorption, and bias |
| `cfg.weather` | Live/manual selection, continuous timeline mode, and manual weather |

Important unit conventions:

| Field | Unit |
|---|---|
| `cfg.gs.Height` | km |
| `cfg.satA.Height` | km |
| `cfg.orbit.Keplerian.SemiMajorAxisKm` | km |
| `cfg.orbit.StateVector.PositionECIKm` | km, ECI |
| `cfg.orbit.StateVector.VelocityECIKmS` | km/s, ECI |
| `cfg.link.SatDistance` | km |
| `cfg.link.Wavelength` | m |
| `cfg.link.Ptx` | dBm |
| `cfg.link.Preq` | dBm |
| `cfg.link.OutageMarginDB` | dB |
| Pointing error, jitter, and bias fields | rad |

## Source files

| File | Responsibility |
|---|---|
| `ogs_gui.m` | Builds the GUI, maps controls to configuration, and launches simulations |
| `ogs_config.m` | Defines default ground station, satellites, link, orbit, and weather settings |
| `run_link_budget_live.m` | Computes and prints a single link-budget snapshot |
| `run_link_budget_continuous.m` | Combines trajectory, atmosphere, independent terminal jitter histories, access, margin, and outage calculations |
| `resolve_trajectory.m` | Propagates fixed, Keplerian, or initial-state-vector geometry and calculates ground-relative access |
| `tests/test_resolve_trajectory.m` | Verifies fixed geometry, Keplerian propagation, state-vector propagation, and invalid-orbit rejection |
| `generate_terminal_jitter.m` | Generates configured-random, OLYMPUS, or Micius two-axis terminal motion, including reference after-ATP residuals |
| `fetch_live_weather.m` | Retrieves the latest Open-Meteo conditions |
| `fetch_weather_history.m` | Retrieves the recent 15-minute weather window |
| `classify_attenuation.m` | Maps WMO weather codes to clear, rain, or snow attenuation |
| `compute_atmospheric_loss.m` | Calculates shared geometrical, Mie, and absorption losses |
| `python/run.py` | Launches the Python desktop application |
| `python/ogs_linkbudget/` | Contains the Python configuration, physics, weather, simulation, GUI, and chart modules |
| `python/ogs_linkbudget/trajectory.py` | Implements fixed, Keplerian, and initial-state-vector trajectory geometry in Python |
| `python/tests/` | Verifies the Python geometry and simulation behavior without network access |

## Model scope

- Both applications support fixed worst-case geometry, Keplerian elements, and an initial ECI state vector for ground-space links.
- Keplerian and state-vector propagation uses a two-body Earth model. It omits drag, oblateness, third-body forces, maneuvers, attitude, and orbit-estimation uncertainty.
- The moving modes treat their elements or state vector as valid at the simulation start; catalog lookup and TLE/OMM import are intentionally outside this simple tester.
- Atmospheric weather remains tied to the configured ground station. The model changes air mass with elevation but does not resolve spatially varying weather along the slanted beam path.
- Inter-satellite range is a fixed configured distance.
- Open-Meteo supplies model data rather than direct measurements from a dedicated station at the entered coordinates.
- Historical weather replay uses 15-minute samples and interpolates atmospheric loss across the signal timeline.
- Current Hold assumes weather remains unchanged for the selected future duration.
- Configured Random has no temporal correlation; OLYMPUS uses its analytic PSD and reference residual target, while Micius uses band-shaped approximations of its published before- and after-ATP measurements.
- The simulator does not model a pointing-control transfer function, reaction-wheel operating states, or other satellite attitude-control dynamics.

# Python Simulator

This folder contains a standard-library Python version of the optical link-budget simulator. It follows the same scenario, hardware, atmospheric-loss, snapshot, continuous-jitter, and outage models as the MATLAB application.

## Requirements

- Python 3.10 or newer
- Tkinter, which is included with the standard Python installers from [python.org](https://www.python.org/downloads/)
- Internet access when **Live API** weather is selected

No `pip` packages, virtual environment, MATLAB installation, or API key are required.

## Run from a downloaded ZIP

1. Download and extract the project ZIP.
2. Open Terminal or Command Prompt in the extracted project folder.
3. Run:

```bash
python3 python/run.py
```

On Windows, use this command if `python3` is not recognized:

```powershell
py python\run.py
```

## Install from PyPI

The packaged application can be installed and launched with:

```bash
python3 -m pip install ogs-linkbudget-live
ogs-linkbudget
```

## Features

- Downlink, uplink, and inter-satellite links
- User-selected worst-case elevation for ground-space links
- Manual weather or live Open-Meteo conditions
- Past Replay and Current Hold continuous weather timelines
- Independent transmitter and receiver jitter-profile selection
- Configured random, OLYMPUS open-loop/reference ATP, and Micius before/after-ATP jitter
- Ideal no-weather/no-jitter reference margin
- User-configurable operational outage margin with a `3 dB` default
- Dynamic margin, probability-density, and outage charts

Each continuous run creates a fresh random jitter sequence. No seed is requested from the user.

## Interface

The Scenario Settings tab selects the link direction, conservative elevation, weather source, station location, simulation mode, weather timeline, and duration.

- **OLYMPUS Platform PSD (Open Loop)** uses `S(f) = 160/(1 + f²) µrad²/Hz`, approximately `15.85 µrad` radial RMS, at 200 Hz.
- **OLYMPUS After ATP (Reference Design)** uses the same modeled disturbance shape calibrated to a published `0.34 µrad` optical-terminal residual target. It is a design reference rather than a measured OLYMPUS closed-loop flight spectrum.
- **Micius Before ATP (Open Loop)** reproduces its published `0–1`, `1–10`, `10–50`, and `50–100 Hz` band RMS values, approximately `9.26 µrad` combined, at 250 Hz.
- **Micius After ATP (Measured)** reproduces the published residual values in the same bands, approximately `0.48 µrad` combined (`0.47 µrad` reported full-band).

<p align="center">
  <img src="https://raw.githubusercontent.com/reptide/ogs-linkbudget-live/main/images/python/python_gui_panel1.png" width="550" alt="Python Scenario Settings tab">
  <br>
  <em>Python scenario and continuous-simulation controls.</em>
</p>

The Hardware Configuration tab defines transmitter power, wavelength, terminal apertures, configured-random per-axis jitter, relative boresight bias, and the required operational margin. The margin defaults to `3 dB` and can be configured from `0` to `30 dB`. A terminal's entered jitter value is only used when **Configured Random** is selected.

ATP profiles contain residual tracking error after a closed-loop pointing system, whose rejection varies with frequency and controller behavior. Manual suppression instead scales every angular sample by `10^(-dB/20)` and PSD power by `10^(-dB/10)`. Leave it at `0 dB` to use an after-ATP reference by itself; a nonzero value adds hypothetical frequency-independent suppression after that residual.

Because the available OLYMPUS-based reference gives an integrated residual target rather than a closed-loop residual spectrum, its after-ATP option is equivalent here to approximately `33.4 dB` of uniform suppression. The Micius after-ATP option instead uses measured band-dependent residuals and therefore changes the spectral shape.

The Jitter Models tab contains the independent Tx/Rx profile selectors and their `0–60 dB` additional-suppression controls. It keeps all Configured Random, OLYMPUS, and Micius choices together. The tab’s controls are enabled only for Continuous Tracking.

<p align="center">
  <img src="https://raw.githubusercontent.com/reptide/ogs-linkbudget-live/main/images/python/python_gui_panel2.png" width="550" alt="Python Hardware Configuration tab">
  <br>
  <em>Python optical hardware and pointing controls.</em>
</p>

Continuous simulations display the randomized link-margin profile, the ideal no-weather/no-jitter reference, the configurable operational outage threshold, the `0 dB` receiver-sensitivity boundary, the margin probability density, and the calculated outage rate.

<p align="center">
  <img src="https://raw.githubusercontent.com/reptide/ogs-linkbudget-live/main/images/python/python_simulation_result.png" width="700" alt="Python continuous simulation analytics">
  <br>
  <em>Python continuous link-margin and outage analytics.</em>
</p>

## Run the tests

From the project folder:

```bash
python3 -m unittest discover -s python/tests -t python
```

The test suite uses local TLE data and does not require an internet connection.

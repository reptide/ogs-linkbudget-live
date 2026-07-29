"""Tkinter desktop interface for the standard-library Python simulator."""

import math
import threading
import tkinter as tk
from tkinter import messagebox, ttk

from .charts import AnalyticsWindow
from .config import default_config
from .simulation import format_snapshot, run_continuous, run_snapshot


class OGSApplication(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("OGS Live Link Budget Control Panel — Python")
        self.geometry("610x760")
        self.minsize(590, 720)
        self._variables()
        self._build()
        self._update_mode()
        self._update_jitter_labels()

    def _variables(self) -> None:
        defaults = default_config()
        self.link_type = tk.StringVar(value="downlink")
        self.elevation = tk.StringVar(value=str(defaults.orbit.worst_case_elevation_deg))
        self.weather_source = tk.StringVar(value="Live API")
        self.latitude = tk.StringVar(value=str(defaults.ground.latitude_deg))
        self.longitude = tk.StringVar(value=str(defaults.ground.longitude_deg))
        self.altitude_m = tk.StringVar(value=str(defaults.ground.height_km * 1000))
        self.simulation_mode = tk.StringVar(value="Single Snapshot")
        self.weather_timeline = tk.StringVar(value=defaults.weather.continuous_mode)
        self.jitter_model = tk.StringVar(value="Rayleigh (No Bias)")
        self.duration_minutes = tk.StringVar(value="1")
        self.tx_power_w = tk.StringVar(value="10")
        self.wavelength_nm = tk.StringVar(value="1550")
        self.tx_aperture_m = tk.StringVar(value="0.3")
        self.rx_aperture_m = tk.StringVar(value="0.3")
        self.first_jitter_urad = tk.StringVar(value="2")
        self.second_jitter_urad = tk.StringVar(value="1")
        self.boresight_urad = tk.StringVar(value="0")
        self.status = tk.StringVar(value="Status: Control panel ready.")

    def _build(self) -> None:
        self.columnconfigure(0, weight=1)
        self.rowconfigure(0, weight=1)
        notebook = ttk.Notebook(self)
        notebook.grid(row=0, column=0, padx=18, pady=(18, 8), sticky="nsew")
        scenario = ttk.Frame(notebook, padding=16)
        hardware = ttk.Frame(notebook, padding=16)
        notebook.add(scenario, text="Scenario Settings")
        notebook.add(hardware, text="Hardware Configuration")
        scenario.columnconfigure(1, weight=1)
        hardware.columnconfigure(1, weight=1)

        self._combo(
            scenario,
            0,
            "Link Direction:",
            self.link_type,
            ("downlink", "uplink", "inter-satellite"),
            self._update_jitter_labels,
        )
        self._entry(scenario, 1, "Worst-case Elevation (deg):", self.elevation)

        ttk.Label(scenario, text="Atmosphere Data:").grid(
            row=2, column=0, padx=8, pady=8, sticky="e"
        )
        weather_frame = ttk.Frame(scenario)
        weather_frame.grid(row=2, column=1, sticky="w")
        for value in ("Live API", "Manual"):
            ttk.Radiobutton(
                weather_frame, text=value, value=value, variable=self.weather_source
            ).pack(side="left", padx=5)

        self._entry(scenario, 3, "Station Latitude (deg N):", self.latitude)
        self._entry(scenario, 4, "Station Longitude (deg E):", self.longitude)
        self._entry(scenario, 5, "Station Alt AMSL (m):", self.altitude_m)

        ttk.Label(scenario, text="Simulation Mode:").grid(
            row=6, column=0, padx=8, pady=8, sticky="e"
        )
        mode_frame = ttk.Frame(scenario)
        mode_frame.grid(row=6, column=1, sticky="w")
        for value in ("Single Snapshot", "Continuous Tracking"):
            ttk.Radiobutton(
                mode_frame,
                text=value,
                value=value,
                variable=self.simulation_mode,
                command=self._update_mode,
            ).pack(anchor="w")

        self.continuous_frame = ttk.LabelFrame(
            scenario, text="Continuous Simulation Sub-settings", padding=12
        )
        self.continuous_frame.grid(
            row=7, column=0, columnspan=2, pady=(12, 4), sticky="ew"
        )
        self.continuous_frame.columnconfigure(1, weight=1)
        self._combo(
            self.continuous_frame,
            0,
            "Live Weather Timeline:",
            self.weather_timeline,
            ("Past Replay", "Current Hold"),
        )
        self._combo(
            self.continuous_frame,
            1,
            "Jitter Model:",
            self.jitter_model,
            ("Rayleigh (No Bias)", "Rician (With Bias)"),
        )
        self._entry(
            self.continuous_frame, 2, "Duration (minutes):", self.duration_minutes
        )

        self._entry(hardware, 0, "Tx Laser Power (W):", self.tx_power_w)
        self._entry(hardware, 1, "Wavelength (nm):", self.wavelength_nm)
        self._entry(hardware, 2, "Tx Aperture Diameter (m):", self.tx_aperture_m)
        self._entry(hardware, 3, "Rx Aperture Diameter (m):", self.rx_aperture_m)
        self.first_jitter_label = ttk.Label(hardware, text="Satellite Jitter (µrad):")
        self.first_jitter_label.grid(row=4, column=0, padx=8, pady=9, sticky="e")
        ttk.Entry(hardware, textvariable=self.first_jitter_urad, width=18).grid(
            row=4, column=1, padx=8, pady=9, sticky="w"
        )
        self.second_jitter_label = ttk.Label(hardware, text="Ground Jitter (µrad):")
        self.second_jitter_label.grid(row=5, column=0, padx=8, pady=9, sticky="e")
        ttk.Entry(hardware, textvariable=self.second_jitter_urad, width=18).grid(
            row=5, column=1, padx=8, pady=9, sticky="w"
        )
        self._entry(hardware, 6, "Boresight Bias (µrad):", self.boresight_urad)

        self.run_button = ttk.Button(
            self, text="RUN LINK BUDGET", command=self._run
        )
        self.run_button.grid(row=1, column=0, padx=18, pady=10, sticky="ew", ipady=10)
        ttk.Label(self, textvariable=self.status).grid(
            row=2, column=0, padx=20, pady=(0, 16), sticky="w"
        )

    @staticmethod
    def _entry(parent: ttk.Frame, row: int, label: str, variable: tk.StringVar) -> None:
        ttk.Label(parent, text=label).grid(row=row, column=0, padx=8, pady=9, sticky="e")
        ttk.Entry(parent, textvariable=variable, width=22).grid(
            row=row, column=1, padx=8, pady=9, sticky="w"
        )

    @staticmethod
    def _combo(
        parent: ttk.Frame,
        row: int,
        label: str,
        variable: tk.StringVar,
        values: tuple[str, ...],
        callback=None,
    ) -> None:
        ttk.Label(parent, text=label).grid(row=row, column=0, padx=8, pady=9, sticky="e")
        combo = ttk.Combobox(
            parent, textvariable=variable, values=values, state="readonly", width=25
        )
        combo.grid(row=row, column=1, padx=8, pady=9, sticky="w")
        if callback:
            combo.bind("<<ComboboxSelected>>", lambda _event: callback())

    def _update_mode(self) -> None:
        continuous = self.simulation_mode.get() == "Continuous Tracking"
        for child in self.continuous_frame.winfo_children():
            try:
                if continuous and isinstance(child, ttk.Combobox):
                    child.configure(state="readonly")
                else:
                    child.configure(state="normal" if continuous else "disabled")
            except tk.TclError:
                pass

    def _update_jitter_labels(self) -> None:
        if self.link_type.get() == "inter-satellite":
            self.first_jitter_label.configure(text="Satellite A Jitter (µrad):")
            self.second_jitter_label.configure(text="Satellite B Jitter (µrad):")
        else:
            self.first_jitter_label.configure(text="Satellite Jitter (µrad):")
            self.second_jitter_label.configure(text="Ground Jitter (µrad):")

    @staticmethod
    def _number(variable: tk.StringVar, name: str, minimum=None, maximum=None) -> float:
        try:
            value = float(variable.get())
        except ValueError as error:
            raise ValueError(f"{name} must be numeric.") from error
        if minimum is not None and value < minimum:
            raise ValueError(f"{name} must be at least {minimum}.")
        if maximum is not None and value > maximum:
            raise ValueError(f"{name} must be at most {maximum}.")
        return value

    def _config_from_controls(self):
        config = default_config()
        config.link.link_type = self.link_type.get()
        config.orbit.worst_case_elevation_deg = self._number(
            self.elevation, "Worst-case elevation", 5, 90
        )
        config.weather.use_live = self.weather_source.get() == "Live API"
        config.weather.continuous_mode = self.weather_timeline.get()
        config.ground.latitude_deg = self._number(self.latitude, "Latitude", -90, 90)
        config.ground.longitude_deg = self._number(
            self.longitude, "Longitude", -180, 180
        )
        config.ground.height_km = self._number(
            self.altitude_m, "Station altitude", 0, 9000
        ) / 1000.0

        power_w = self._number(self.tx_power_w, "Transmit power", 0.000001)
        config.link.transmit_power_dbm = 10.0 * math.log10(power_w * 1000.0)
        config.link.wavelength_m = self._number(
            self.wavelength_nm, "Wavelength", 1
        ) * 1e-9
        tx_aperture = self._number(self.tx_aperture_m, "Tx aperture", 0.000001)
        rx_aperture = self._number(self.rx_aperture_m, "Rx aperture", 0.000001)
        if config.link.link_type == "uplink":
            config.ground.aperture_diameter_m = tx_aperture
            config.satellite_a.aperture_diameter_m = rx_aperture
        elif config.link.link_type == "inter-satellite":
            config.satellite_a.aperture_diameter_m = tx_aperture
            config.satellite_b.aperture_diameter_m = rx_aperture
        else:
            config.satellite_a.aperture_diameter_m = tx_aperture
            config.ground.aperture_diameter_m = rx_aperture

        first_jitter = self._number(
            self.first_jitter_urad, "First terminal jitter", 0
        ) * 1e-6
        second_jitter = self._number(
            self.second_jitter_urad, "Second terminal jitter", 0
        ) * 1e-6
        config.satellite_a.jitter_sigma_rad = first_jitter
        if config.link.link_type == "inter-satellite":
            config.satellite_b.jitter_sigma_rad = second_jitter
        else:
            config.ground.jitter_sigma_rad = second_jitter
        config.link.boresight_bias_rad = self._number(
            self.boresight_urad, "Boresight bias", 0
        ) * 1e-6
        return config

    def _run(self) -> None:
        try:
            config = self._config_from_controls()
            duration_seconds = (
                self._number(self.duration_minutes, "Duration", 1, 60) * 60.0
                if self.simulation_mode.get() == "Continuous Tracking"
                else 60.0
            )
        except ValueError as error:
            messagebox.showerror("Invalid configuration", str(error), parent=self)
            return

        self.run_button.configure(state="disabled")
        self.status.set("Status: Running simulation...")
        mode = self.simulation_mode.get()
        jitter_model = self.jitter_model.get()

        def worker() -> None:
            try:
                if mode == "Single Snapshot":
                    result = run_snapshot(config)
                else:
                    result = run_continuous(config, duration_seconds, 0.1, jitter_model)
                self.after(0, lambda: self._show_result(mode, result))
            except Exception as error:
                self.after(0, lambda captured=error: self._show_error(captured))

        threading.Thread(target=worker, daemon=True).start()

    def _show_result(self, mode: str, result) -> None:
        self.run_button.configure(state="normal")
        self.status.set("Status: Simulation complete.")
        if mode == "Single Snapshot":
            window = tk.Toplevel(self)
            window.title("Link Budget Snapshot")
            window.geometry("600x430")
            text = tk.Text(window, wrap="none", font=("Courier", 11), padx=16, pady=16)
            text.insert("1.0", format_snapshot(result))
            text.configure(state="disabled")
            text.pack(fill="both", expand=True)
        else:
            AnalyticsWindow(self, result)

    def _show_error(self, error: Exception) -> None:
        self.run_button.configure(state="normal")
        self.status.set("Status: Simulation failed.")
        messagebox.showerror("Simulation error", str(error), parent=self)


def launch() -> None:
    app = OGSApplication()
    app.mainloop()

"""Resizable Tkinter Canvas charts for continuous simulation results."""

import math
import tkinter as tk

from .simulation import ContinuousResult


class AnalyticsWindow(tk.Toplevel):
    """Display margin history, probability density, and outage rate."""

    def __init__(self, parent: tk.Misc, result: ContinuousResult) -> None:
        super().__init__(parent)
        self.result = result
        self.title("Continuous Dynamic Performance Simulation Analytics")
        self.geometry("1050x800")
        self.minsize(820, 620)
        self.canvas = tk.Canvas(self, background="white", highlightthickness=0)
        self.canvas.pack(fill="both", expand=True)
        self.canvas.bind("<Configure>", self._redraw)

    def _redraw(self, _event: tk.Event | None = None) -> None:
        self.canvas.delete("all")
        width = max(self.canvas.winfo_width(), 820)
        height = max(self.canvas.winfo_height(), 620)
        margin = 55
        gap = 70
        top_height = int(height * 0.48)
        lower_top = top_height + 105
        lower_width = (width - 2 * margin - gap) / 2

        self._draw_margin((margin, 45, width - margin, top_height))
        self._draw_pdf((margin, lower_top, margin + lower_width, height - margin))
        self._draw_outage(
            (margin + lower_width + gap, lower_top, width - margin, height - margin)
        )

    @staticmethod
    def _map(
        value: float,
        source_min: float,
        source_max: float,
        target_min: float,
        target_max: float,
    ) -> float:
        if source_max == source_min:
            return (target_min + target_max) / 2
        ratio = (value - source_min) / (source_max - source_min)
        return target_min + ratio * (target_max - target_min)

    def _axes(
        self,
        rect: tuple[float, float, float, float],
        title: str,
        x_label: str,
        y_label: str,
        x_ticks: list[tuple[float, str]],
        y_ticks: list[tuple[float, str]],
        x_limits: tuple[float, float],
        y_limits: tuple[float, float],
    ) -> tuple[float, float, float, float]:
        left, top, right, bottom = rect
        plot_left = left + 65
        plot_top = top + 30
        plot_right = right - 15
        plot_bottom = bottom - 55

        self.canvas.create_text(
            (left + right) / 2,
            top,
            text=title,
            font=("TkDefaultFont", 13, "bold"),
        )
        self.canvas.create_rectangle(
            plot_left, plot_top, plot_right, plot_bottom, outline="#555555"
        )

        for value, label in x_ticks:
            x = self._map(value, *x_limits, plot_left, plot_right)
            self.canvas.create_line(x, plot_top, x, plot_bottom, fill="#dddddd")
            self.canvas.create_text(x, plot_bottom + 18, text=label, font=("TkDefaultFont", 9))
        for value, label in y_ticks:
            y = self._map(value, *y_limits, plot_bottom, plot_top)
            self.canvas.create_line(plot_left, y, plot_right, y, fill="#dddddd")
            self.canvas.create_text(
                plot_left - 9,
                y,
                text=label,
                anchor="e",
                font=("TkDefaultFont", 9),
            )

        self.canvas.create_text(
            (plot_left + plot_right) / 2,
            bottom - 13,
            text=x_label,
            font=("TkDefaultFont", 10),
        )
        self.canvas.create_text(
            left + 13,
            (plot_top + plot_bottom) / 2,
            text=y_label,
            angle=90,
            font=("TkDefaultFont", 10),
        )
        return plot_left, plot_top, plot_right, plot_bottom

    @staticmethod
    def _ticks(minimum: float, maximum: float, count: int = 5) -> list[float]:
        if maximum == minimum:
            return [minimum]
        return [minimum + index * (maximum - minimum) / count for index in range(count + 1)]

    def _time_ticks(self, count: int = 4) -> list[tuple[float, str]]:
        end = self.result.elapsed_seconds[-1]
        values = [index * end / count for index in range(count + 1)]
        if self.result.plot_times_utc:
            start = self.result.plot_times_utc[0]
            labels = [
                (start.timestamp() + value)
                for value in values
            ]
            from datetime import datetime, timezone

            return [
                (value, datetime.fromtimestamp(stamp, timezone.utc).strftime("%H:%M"))
                for value, stamp in zip(values, labels)
            ]
        return [(value, f"{value:.0f}") for value in values]

    def _draw_margin(self, rect: tuple[float, float, float, float]) -> None:
        margins = self.result.margins_db
        ideal = self.result.ideal_margin_db
        outage_margin = self.result.outage_margin_db
        y_min = max(
            -100.0, min(min(margins), 0.0, outage_margin, ideal) - 10.0
        )
        y_max = max(
            20.0, max(max(margins), 0.0, outage_margin, ideal) + 10.0
        )
        y_values = self._ticks(y_min, y_max)
        y_ticks = [(value, f"{value:.0f}") for value in y_values]
        x_end = self.result.elapsed_seconds[-1]
        title = f"Dynamic Margin Profile — {self.result.jitter_model}"
        if self.result.elevation_deg is not None:
            title += f" — Worst-case Elevation {self.result.elevation_deg:.1f}°"
        plot = self._axes(
            rect,
            title,
            self.result.time_axis_label,
            "Link Margin (dB)",
            self._time_ticks(),
            y_ticks,
            (0.0, x_end),
            (y_min, y_max),
        )
        left, top, right, bottom = plot

        def y_pixel(value: float) -> float:
            return self._map(value, y_min, y_max, bottom, top)

        if outage_margin != 0.0:
            zero_y = y_pixel(0.0)
            self.canvas.create_line(
                left, zero_y, right, zero_y, fill="#777777", dash=(3, 4)
            )
            self.canvas.create_text(
                right - 4,
                zero_y + 10,
                text="Receiver Sensitivity Boundary (0 dB)",
                fill="#666666",
                anchor="e",
            )

        outage_y = y_pixel(outage_margin)
        self.canvas.create_line(
            left, outage_y, right, outage_y, fill="red", dash=(8, 5), width=2
        )
        self.canvas.create_text(
            right - 4,
            outage_y - 9,
            text=f"Operational Outage Threshold ({outage_margin:g} dB)",
            fill="red",
            anchor="e",
        )

        reference_y = y_pixel(ideal)
        self.canvas.create_line(
            left, reference_y, right, reference_y, fill="#008030", dash=(8, 4, 2, 4), width=2
        )
        reference_name = (
            "No Jitter Loss"
            if self.result.link_type == "inter-satellite"
            else "No Atmospheric/Jitter Loss"
        )
        self.canvas.create_text(
            left + 4,
            reference_y + 10,
            text=f"Reference: {reference_name} ({ideal:.1f} dB)",
            fill="#008030",
            anchor="w",
        )

        max_points = max(500, int(right - left) * 2)
        step = max(1, math.ceil(len(margins) / max_points))
        points: list[float] = []
        for index in range(0, len(margins), step):
            x = self._map(
                self.result.elapsed_seconds[index], 0.0, x_end, left, right
            )
            points.extend((x, y_pixel(margins[index])))
        if len(points) >= 4:
            self.canvas.create_line(*points, fill="#0066dd", width=1)

    @staticmethod
    def _histogram(values: list[float], bin_count: int = 45) -> tuple[list[float], list[float]]:
        minimum = min(values)
        maximum = max(values)
        if maximum == minimum:
            minimum -= 0.5
            maximum += 0.5
        width = (maximum - minimum) / bin_count
        counts = [0] * bin_count
        for value in values:
            index = min(bin_count - 1, int((value - minimum) / width))
            counts[index] += 1
        density = [count / (len(values) * width) for count in counts]
        edges = [minimum + index * width for index in range(bin_count + 1)]
        return edges, density

    def _draw_pdf(self, rect: tuple[float, float, float, float]) -> None:
        edges, density = self._histogram(self.result.margins_db)
        y_max = max(density) * 1.12 if max(density) else 1.0
        x_ticks_values = self._ticks(edges[0], edges[-1], 4)
        y_ticks_values = self._ticks(0.0, y_max, 4)
        plot = self._axes(
            rect,
            "Margin Probability Density Function (PDF)",
            "Margin (dB)",
            "PDF",
            [(value, f"{value:.1f}") for value in x_ticks_values],
            [(value, f"{value:.2g}") for value in y_ticks_values],
            (edges[0], edges[-1]),
            (0.0, y_max),
        )
        left, top, right, bottom = plot
        for index, value in enumerate(density):
            x0 = self._map(edges[index], edges[0], edges[-1], left, right)
            x1 = self._map(edges[index + 1], edges[0], edges[-1], left, right)
            y = self._map(value, 0.0, y_max, bottom, top)
            self.canvas.create_rectangle(
                x0, y, x1, bottom, fill="#85b84b", outline="#263813"
            )

    def _draw_outage(self, rect: tuple[float, float, float, float]) -> None:
        plot = self._axes(
            rect,
            (
                "Calculated Link Outage Rate "
                f"(< {self.result.outage_margin_db:g} dB)"
            ),
            "Time in Outage (%)",
            "Outage (%)",
            [(0.5, "")],
            [(value, f"{value:.0f}") for value in range(0, 101, 20)],
            (0.0, 1.0),
            (0.0, 100.0),
        )
        left, top, right, bottom = plot
        center = (left + right) / 2
        bar_width = (right - left) * 0.24
        value = self.result.outage_rate_pct
        y = self._map(value, 0.0, 100.0, bottom, top)
        self.canvas.create_rectangle(
            center - bar_width / 2,
            y,
            center + bar_width / 2,
            bottom,
            fill="#dc5815",
            outline="#7a2e08",
        )
        self.canvas.create_text(
            center,
            max(top + 14, y - 12),
            text=f"{value:.1f}%",
            font=("TkDefaultFont", 12, "bold"),
        )

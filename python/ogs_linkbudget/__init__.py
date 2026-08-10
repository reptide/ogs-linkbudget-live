"""Standard-library Python implementation of the OGS link budget simulator."""

from .config import SimulatorConfig, default_config
from .simulation import ContinuousResult, SnapshotResult, run_continuous, run_snapshot
from .trajectory import TrajectoryGeometry, resolve_trajectory

__version__ = "3.2.0"

__all__ = [
    "ContinuousResult",
    "SimulatorConfig",
    "SnapshotResult",
    "TrajectoryGeometry",
    "__version__",
    "default_config",
    "run_continuous",
    "run_snapshot",
    "resolve_trajectory",
]

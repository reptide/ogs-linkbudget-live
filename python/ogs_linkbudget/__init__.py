"""Standard-library Python implementation of the OGS link budget simulator."""

from .config import SimulatorConfig, default_config
from .simulation import ContinuousResult, SnapshotResult, run_continuous, run_snapshot

__version__ = "2.2.0"

__all__ = [
    "ContinuousResult",
    "SimulatorConfig",
    "SnapshotResult",
    "__version__",
    "default_config",
    "run_continuous",
    "run_snapshot",
]

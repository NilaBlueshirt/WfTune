#!/usr/bin/env python3
"""Run ``wftune plot energy`` from a source checkout; the code is in src/wftune/."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from wftune.plot_energy import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main())

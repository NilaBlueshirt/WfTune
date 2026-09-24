#!/usr/bin/env python3
"""Run ``wftune demo`` from a source checkout; the code is in src/wftune/."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from wftune.make_fixture import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main())

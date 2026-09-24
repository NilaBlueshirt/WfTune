"""Offline audit, summary, and plotting tools for WfTune campaigns."""
from importlib.metadata import version
from pathlib import Path

# A source checkout keeps the release in VERSION at the repository root, spelled
# exactly as the collection harness records it.  An installed package reports
# its own metadata instead.
_CHECKOUT_VERSION = Path(__file__).resolve().parents[2] / "VERSION"
if _CHECKOUT_VERSION.is_file():
    __version__ = _CHECKOUT_VERSION.read_text(encoding="utf-8").rstrip("\n")
else:
    __version__ = version("wftune")

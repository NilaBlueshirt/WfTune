#!/usr/bin/env python3
"""Compare clean-start walltime and total attributable RPC across WMS roots.

Each WMS keeps an independent monitor root so its frozen pipeline/configuration
contract is audited internally.  This script validates each root with the
inherited campaign checker, then joins only the two metrics that are meaningful
for both native Nextflow traces and the workflow-level Snakemake trace.

Example::

    python analysis/plot_cross_wms.py \
      --series Nextflow=/path/to/monitor/nextflow \
      --series Snakemake=/path/to/monitor/snakemake \
      --venue cluster-a --through-rep 3 --backends native,jobarray \
      --out cross-wms.pdf --csv cross-wms.csv
"""
from __future__ import annotations

import argparse
import csv
import math
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

from campaign import BACKEND_LABELS, CampaignError, validate_campaign


def parse_series(value: str) -> tuple[str, Path]:
    label, separator, root = value.partition("=")
    if not separator or not label.strip() or not root.strip():
        raise argparse.ArgumentTypeError("series must be LABEL=/absolute/monitor/root")
    path = Path(root).expanduser()
    if not path.is_absolute():
        raise argparse.ArgumentTypeError("series monitor roots must be absolute")
    return label.strip(), path


def parse_backends(value: str) -> list[str]:
    selected = [item.strip() for item in value.split(",") if item.strip()]
    if not selected:
        raise argparse.ArgumentTypeError("select at least one backend")
    unknown = [item for item in selected if item not in BACKEND_LABELS]
    if unknown:
        raise argparse.ArgumentTypeError(f"unknown backends: {unknown}")
    if len(set(selected)) != len(selected):
        raise argparse.ArgumentTypeError("backends may not repeat")
    return selected


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument(
        "--series", action="append", type=parse_series, required=True,
        metavar="LABEL=ROOT",
        help="repeat once per WMS; each root is validated independently",
    )
    result.add_argument("--venue", required=True)
    result.add_argument("--through-rep", required=True, type=int)
    result.add_argument(
        "--backends", type=parse_backends, default=parse_backends("native,jobarray")
    )
    result.add_argument("--out", required=True, type=Path)
    result.add_argument("--csv", type=Path)
    return result


def load(args: argparse.Namespace) -> list[dict]:
    if args.through_rep <= 0:
        raise CampaignError("--through-rep must be positive")
    labels = [label for label, _ in args.series]
    if len(labels) < 2 or len(set(labels)) != len(labels):
        raise CampaignError("provide at least two uniquely labeled --series values")
    rows: list[dict] = []
    recorded_by_label: dict[str, str] = {}
    for label, root in args.series:
        campaign = validate_campaign(
            root,
            through_rep=args.through_rep,
            venues=[args.venue],
            backends=args.backends,
        )
        recorded = {str(row.get("wms") or "").strip() for row in campaign}
        if len(recorded) != 1 or "" in recorded:
            raise CampaignError(f"{root}: expected exactly one recorded WMS, got {recorded}")
        recorded_by_label[label] = recorded.pop()
        for row in campaign:
            walltime_h = float(row["walltime_s"]) / 3600.0
            rpc_count = float(row["benchmark_rpc_count"])
            if not math.isfinite(walltime_h) or not math.isfinite(rpc_count):
                raise CampaignError(f"{row['run_dir']}: non-finite cross-WMS metric")
            rows.append(
                {
                    "wms_label": label,
                    "wms_recorded": recorded_by_label[label],
                    "venue": row["venue"],
                    "replicate": int(row["replicate"]),
                    "backend": row["backend"],
                    "walltime_h": walltime_h,
                    "rpc_count": rpc_count,
                    "run_dir": row["run_dir"],
                }
            )
    if len(set(recorded_by_label.values())) != len(recorded_by_label):
        raise CampaignError(
            f"series must represent distinct WMSs, got {recorded_by_label}"
        )
    return rows


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "wms_label", "wms_recorded", "venue", "replicate", "backend",
        "walltime_h", "rpc_count", "run_dir",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def render(path: Path, rows: list[dict], series: list[tuple[str, Path]],
           backends: list[str]) -> None:
    combinations = [
        (label, backend) for label, _ in series for backend in backends
    ]
    labels = [
        f"{label}\n{BACKEND_LABELS.get(backend, backend)}"
        for label, backend in combinations
    ]
    colors = plt.get_cmap("tab10")(np.linspace(0.0, 0.8, len(combinations)))
    figure, axes = plt.subplots(1, 2, figsize=(7.16, 3.0))
    for axis, metric, ylabel, log_scale in (
        (axes[0], "walltime_h", "Clean-start walltime (h)", False),
        (axes[1], "rpc_count", "Attributable RPC count", True),
    ):
        medians: dict[tuple[str, str], float] = {}
        for index, ((wms_label, backend), color) in enumerate(
            zip(combinations, colors)
        ):
            values = np.asarray(
                [
                    row[metric] for row in rows
                    if row["wms_label"] == wms_label and row["backend"] == backend
                ],
                dtype=float,
            )
            if values.size == 0:
                raise CampaignError(f"missing {wms_label}/{backend} observations")
            offsets = np.linspace(-0.10, 0.10, values.size)
            axis.scatter(index + offsets, values, color=color, s=18, alpha=0.60,
                         linewidths=0, zorder=2)
            median = float(np.median(values))
            medians[(wms_label, backend)] = median
            axis.errorbar(
                index, median,
                yerr=[[median - float(values.min())], [float(values.max()) - median]],
                fmt="D", color=color, markeredgecolor="black", markeredgewidth=0.4,
                capsize=3, markersize=5, zorder=3,
            )
        axis.set_xticks(range(len(labels)), labels, rotation=22, ha="right")
        axis.set_ylabel(ylabel)
        axis.grid(axis="y", alpha=0.25)
        if log_scale:
            axis.set_yscale("log")
        if "native" in backends and "jobarray" in backends:
            for wms_label, _ in series:
                native_index = combinations.index((wms_label, "native"))
                array_index = combinations.index((wms_label, "jobarray"))
                ratio = (
                    medians[(wms_label, "jobarray")]
                    / medians[(wms_label, "native")]
                )
                axis.text(
                    (native_index + array_index) / 2,
                    0.98,
                    f"array/native={ratio:.3g}",
                    transform=axis.get_xaxis_transform(),
                    ha="center",
                    va="top",
                    fontsize=7,
                )
    axes[0].set_title("(a) User-facing completion")
    axes[1].set_title("(b) Slurm control-plane demand")
    figure.tight_layout()
    path.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(path, bbox_inches="tight")
    plt.close(figure)


def main() -> int:
    args = parser().parse_args()
    try:
        rows = load(args)
        render(args.out, rows, args.series, args.backends)
        if args.csv:
            write_csv(args.csv, rows)
    except (CampaignError, OSError, ValueError) as error:
        print(f"cross-WMS plot refused: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

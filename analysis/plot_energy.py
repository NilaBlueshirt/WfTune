#!/usr/bin/env python3
"""plot_energy.py — per-backend energy + power-vs-time profiles + RAPL/PDU gap.

Consumes an exclusive-node energy subset:
    ROOT/<venue>/energy/<backend>/rapl/rapl_*.csv
    ROOT/<venue>/energy/<backend>/pdu/pdu.csv
    ROOT/<venue>/energy/<backend>/results/

RAPL energy = sum over domains of differenced energy_uj (wraparound-corrected
using max_energy_range_uj), integrated over the window -> kWh.
PDU energy   = trapezoidal integral of whole-node watts over time -> kWh.
Reports kWh per run and kWh per output-GB, plus the RAPL/PDU fraction.

Two figures:
    fig_energy_bar.png       per-backend kWh/run and kWh/output-GB, RAPL vs PDU
    fig_energy_profile.png   PDU whole-node power vs time, representative backends

Calibration mode reports just the RAPL/PDU gap on the reference workload:
    plot_energy.py --calib bench/calib

usage: plot_energy.py ROOT --venue VENUE [--venue VENUE ...]
       plot_energy.py --calib CALIB_DIR
"""
import argparse
import sys
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

sys.path.insert(0, str(Path(__file__).resolve().parent))
from campaign import (BACKEND_DARK, BACKEND_LABELS, BACKEND_ORDER,
                      VENUE_LABELS)

J_PER_KWH = 3.6e6

# numpy 2.0 renamed trapz -> trapezoid and removed the old name; the cluster
# analysis env may have either, so bind whichever exists. Do NOT use a nested
# getattr default: it eagerly evaluates np.trapz, which raises on numpy>=2.0.
_trapz = np.trapezoid if hasattr(np, "trapezoid") else np.trapz


def collect_energy(root, venue):
    """Return ``{backend: run_dir}`` for one venue's energy subset."""
    base = Path(root) / venue / "energy"
    if not base.is_dir():
        return {}
    return {
        backend: base / backend
        for backend in BACKEND_ORDER
        if (base / backend).is_dir()
    }


def rapl_kwh(rapl_dir):
    """Sum differenced, wraparound-corrected RAPL energy across all nodes and
    domains -> kWh. Also returns per-node total watts time series for context."""
    files = sorted(Path(rapl_dir).glob("rapl_*.csv"))
    if not files:
        return None
    total_uj = 0.0
    for f in files:
        df = pd.read_csv(f)
        if df.empty:
            continue
        for (_, _), g in df.groupby(["node", "domain"]):
            g = g.sort_values("ts_unix")
            e = g["energy_uj"].values.astype(float)
            mx = g["max_energy_range_uj"].dropna().astype(float)
            wrap = mx.iloc[0] if len(mx) else None
            d = np.diff(e)
            if wrap:                       # correct counter wraparound
                d[d < 0] += wrap
            else:
                d = d[d >= 0]
            total_uj += float(np.sum(d))
    return (total_uj * 1e-6) / J_PER_KWH   # uJ -> J -> kWh


def pdu_series(pdu_csv):
    """Whole-node watts summed across reserved nodes -> (t_seconds, watts)."""
    p = Path(pdu_csv)
    if not p.is_file():
        return None
    df = pd.read_csv(p)
    if df.empty:
        return None
    w = df.groupby("ts_unix")["watts"].sum().sort_index()
    t = w.index.values.astype(float)
    return t - t[0], w.values.astype(float)


def pdu_kwh(pdu_csv):
    s = pdu_series(pdu_csv)
    if s is None:
        return None
    t, w = s
    return float(_trapz(w, t)) / J_PER_KWH   # W*s = J -> kWh


def output_gb(run_dir):
    """Total size (GB) of final pipeline outputs, the useful-work denominator."""
    res = Path(run_dir) / "results"
    if not res.is_dir():
        return None
    total = sum(f.stat().st_size for f in res.rglob("*") if f.is_file())
    return total / 1e9 if total else None


def report_calib(calib_dir):
    cd = Path(calib_dir)
    r = rapl_kwh(cd / "rapl")
    p = pdu_kwh(cd / "pdu" / "pdu.csv")
    print(f"Calibration ({cd}):")
    print(f"  RAPL (CPU pkg + DRAM): {r:.4f} kWh" if r is not None else "  RAPL: n/a")
    print(f"  PDU  (whole node)    : {p:.4f} kWh" if p is not None else "  PDU:  n/a")
    if r is not None and p is not None and p > 0:
        frac = 100.0 * r / p
        print(f"  RAPL captures {frac:.1f}% of whole-node energy; "
              f"gap = {100 - frac:.1f}% (NIC/disk/fans/PSU).")
        print(f'  Paper: "RAPL captured {frac:.0f}% of whole-node energy, '
              f'the remaining {100 - frac:.0f}% attributable to '
              'NIC, disks, fans, and PSU loss."')


def plot_one(root, venue):
    energy = collect_energy(root, venue)
    if not energy:
        print(f"no energy data under {root}/{venue}/energy"); return

    rows = ["backend,rapl_kwh,pdu_kwh,output_gb,rapl_kwh_per_gb,pdu_kwh_per_gb,rapl_pdu_frac_pct"]
    bars = {}
    profiles = {}
    for b in BACKEND_ORDER:
        rd = energy.get(b)
        if not rd:
            continue
        r = rapl_kwh(rd / "rapl")
        p = pdu_kwh(rd / "pdu" / "pdu.csv")
        gb = output_gb(rd)
        rpg = (r / gb) if (r and gb) else None
        ppg = (p / gb) if (p and gb) else None
        frac = (100.0 * r / p) if (r and p) else None
        rows.append(f"{b},{r},{p},{gb},{rpg},{ppg},{frac}")
        bars[b] = (r, p, rpg, ppg)
        s = pdu_series(rd / "pdu" / "pdu.csv")
        if s is not None:
            profiles[b] = s

    summary_csv = root / f"energy_summary_{venue}.csv"
    summary_csv.write_text("\n".join(rows) + "\n")
    print(f"wrote {summary_csv}")

    # Figure 1: kWh per run and per output-GB, RAPL vs PDU.
    labels = [BACKEND_LABELS[b] for b in BACKEND_ORDER if b in bars]
    x = np.arange(len(labels))
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(9, 3.6))
    rr = [bars[b][0] or 0 for b in BACKEND_ORDER if b in bars]
    pp = [bars[b][1] or 0 for b in BACKEND_ORDER if b in bars]
    a1.bar(x - 0.2, rr, 0.4, label="RAPL (pkg+DRAM)", color="#aec7e8")
    a1.bar(x + 0.2, pp, 0.4, label="PDU (whole node)", color="#1f77b4")
    a1.set_ylabel("kWh per run"); a1.set_xticks(x)
    a1.set_xticklabels(labels, rotation=20, ha="right", fontsize=8)
    a1.legend(fontsize=7); a1.grid(True, axis="y", alpha=0.3)
    rpg = [bars[b][2] or 0 for b in BACKEND_ORDER if b in bars]
    ppg = [bars[b][3] or 0 for b in BACKEND_ORDER if b in bars]
    a2.bar(x - 0.2, rpg, 0.4, label="RAPL", color="#aec7e8")
    a2.bar(x + 0.2, ppg, 0.4, label="PDU", color="#1f77b4")
    a2.set_ylabel("kWh per output-GB"); a2.set_xticks(x)
    a2.set_xticklabels(labels, rotation=20, ha="right", fontsize=8)
    a2.legend(fontsize=7); a2.grid(True, axis="y", alpha=0.3)
    fig.suptitle(VENUE_LABELS.get(venue, venue), fontsize=10)
    fig.tight_layout(); fig.savefig(f"fig_energy_bar_{venue}.png", dpi=300)
    print(f"wrote fig_energy_bar_{venue}.png")

    # Figure 2: PDU power-vs-time profiles.
    fig2, ax = plt.subplots(figsize=(5.8, 3.6))
    for b, (t, w) in profiles.items():
        ax.plot(t / 3600.0, w, color=BACKEND_DARK[b], lw=1.8, label=BACKEND_LABELS[b])
    ax.set_xlabel("Wall time (h)"); ax.set_ylabel("Whole-node power (W, PDU)")
    ax.set_title(VENUE_LABELS.get(venue, venue), fontsize=8, loc="left", color="grey")
    ax.grid(True, alpha=0.3); ax.legend(fontsize=7)
    fig2.tight_layout(); fig2.savefig(f"fig_energy_profile_{venue}.png", dpi=300)
    print(f"wrote fig_energy_profile_{venue}.png")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path)
    parser.add_argument("--venue", action="append")
    parser.add_argument("--calib", type=Path)
    args = parser.parse_args()
    if args.calib:
        report_calib(args.calib)
        return
    if args.root is None or not args.venue:
        parser.error("ROOT and at least one --venue are required outside calibration mode")
    for venue in args.venue:
        plot_one(args.root, venue)


if __name__ == "__main__":
    main()

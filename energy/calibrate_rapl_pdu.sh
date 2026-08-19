#!/usr/bin/env bash
# calibrate_rapl_pdu.sh — characterize the RAPL-vs-PDU gap ONCE on a reference
# workload before future pipeline-energy runs.
#
# Runs a compute-bound kernel that pins the CPU near a known utilization on ONE
# exclusive reserved node, while sampling RAPL (node-local) and PDU (whole
# node). ``analysis/plot_energy.py`` then reports what share
# of whole-node energy RAPL's CPU-package+DRAM domains capture on this hardware.
# Reuse that factor to interpret per-backend RAPL where PDU is unavailable.
#
# Reference kernel: stress-ng if present (steady, controllable), else a portable
# busy-loop across all cores. HPL is a heavier alternative if you want a
# realistic FLOP profile.
#
# usage (submit as a 1-node exclusive job in the reservation):
#   sbatch --reservation=$WMSbench_RSV --nodes=1 --exclusive --time=00:30:00 \
#          --export=ALL,WMSbench_OUT=/shared/path/wftune-calib calibrate_rapl_pdu.sh
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
: "${WMSbench_OUT:?set WMSbench_OUT to an absolute output path outside the source checkout}"
OUT=$WMSbench_OUT
[[ $OUT == /* ]] || {
    echo "WMSbench_OUT must be an absolute path" >&2
    exit 2
}
DURATION=${CALIB_SECONDS:-600}       # 10 min of steady load
INTERVAL=${CALIB_INTERVAL:-5}
mkdir -p "$OUT/rapl" "$OUT/pdu"
NODE=$(hostname -s)

echo "Calibration on $NODE for ${DURATION}s ..."

# RAPL sampler on this node.
bash "$HERE/rapl_sampler.sh" "$OUT/rapl/rapl_${NODE}.csv" "$DURATION" "$INTERVAL" &
RAPL_PID=$!

# PDU sampler (needs WMSbench_PDU_* configured; polls this node).
WMSbench_PDU_NODES="$NODE" WMSbench_PDU_OUTLETS="${WMSbench_PDU_OUTLETS:-}" \
    bash "$HERE/pdu_sampler.sh" "$OUT/pdu/pdu.csv" "$DURATION" "$INTERVAL" &
PDU_PID=$!

# Steady compute load across all cores.
NCORES=$(nproc)
if command -v stress-ng >/dev/null; then
    stress-ng --cpu "$NCORES" --cpu-method matrixprod --timeout "${DURATION}s" --metrics-brief \
        > "$OUT/load.log" 2>&1 || true
else
    echo "stress-ng not found; using portable busy-loop on $NCORES cores" | tee "$OUT/load.log"
    for _ in $(seq 1 "$NCORES"); do timeout "${DURATION}s" bash -c 'while :; do :; done' & done
    wait || true
fi

kill "$RAPL_PID" "$PDU_PID" 2>/dev/null || true
echo "Calibration data in $OUT. Report the gap with:"
echo "  python3 analysis/plot_energy.py --calib $OUT"

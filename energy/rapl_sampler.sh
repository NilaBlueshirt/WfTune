#!/usr/bin/env bash
# rapl_sampler.sh — sample Intel RAPL energy counters on THIS compute node.
#
# MUST run on the node whose energy you want (via srun/inside the allocation),
# not on the login node. Reads every intel-rapl package + sub-domain
# (energy_uj) at a fixed interval and appends to a CSV. The reporter
# (``analysis/plot_energy.py``) differentiates the counters and handles wraparound using
# each domain's max_energy_range_uj, which is captured once in the header rows.
#
# Scheduler-agnostic: pure sysfs reads, no sacct, no Slurm dependency. Override
# WMSbench_POWERCAP_ROOT only when the system exposes powercap elsewhere.
#
# usage: rapl_sampler.sh <out_csv> <duration_seconds> [interval_seconds]
#   e.g.  srun -N1 --overlap rapl_sampler.sh rapl_$(hostname -s).csv 3600 10
#
# CSV columns: ts_unix,node,domain,energy_uj,max_energy_range_uj
set -euo pipefail

OUT=${1:?usage: $0 <out_csv> <duration_seconds> [interval]}
DURATION=${2:?usage: $0 <out_csv> <duration_seconds> [interval]}
INTERVAL=${3:-10}
NODE=$(hostname -s)
POWERCAP_ROOT=${WMSbench_POWERCAP_ROOT:-/sys/class/powercap}

# Collect domain dirs that actually expose energy_uj (packages and their
# sub-domains like dram/core). Nested intel-rapl:X:Y dirs are matched by the
# recursive find so DRAM is captured where present.
mapfile -t DOMAINS < <(find "$POWERCAP_ROOT" -maxdepth 3 -name energy_uj 2>/dev/null | xargs -n1 dirname 2>/dev/null | sort -u)
if [ "${#DOMAINS[@]}" -eq 0 ]; then
    echo "no energy domains found under $POWERCAP_ROOT on $NODE" >&2
    exit 1
fi

if [ ! -f "$OUT" ]; then
    echo "ts_unix,node,domain,energy_uj,max_energy_range_uj" > "$OUT"
fi

name_of() {  # human domain name from the sysfs `name` file (package-0, dram, ...)
    cat "$1/name" 2>/dev/null | tr -d ' ' || basename "$1"
}

END=$(( $(date +%s) + DURATION ))
while [ "$(date +%s)" -lt "$END" ]; do
    TS=$(date +%s)
    for d in "${DOMAINS[@]}"; do
        e=$(cat "$d/energy_uj" 2>/dev/null || echo "")
        m=$(cat "$d/max_energy_range_uj" 2>/dev/null || echo "")
        [ -n "$e" ] && echo "${TS},${NODE},$(name_of "$d"),${e},${m}" >> "$OUT"
    done
    sleep "$INTERVAL"
done

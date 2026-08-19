#!/usr/bin/env bash
# pdu_sampler.sh — sample whole-node power from the PDU (ground truth).
#
# PDU access is site-specific, so this script is a thin, pluggable poller. Pick
# ONE of two mechanisms:
#
#  (A) SNMP: set WMSbench_PDU_HOST + a per-outlet power OID. Many managed PDUs expose
#      active power (watts) per outlet under a vendor MIB. Example uses a
#      generic OID template; replace with your PDU's real OID.
#        export WMSbench_PDU_HOST=pdu-rack12.hpc.example.edu
#        export WMSbench_PDU_COMMUNITY=public
#        export WMSbench_PDU_OID_TEMPLATE='.1.3.6.1.4.1.<vendor>.<...>.{OUTLET}'
#        export WMSbench_PDU_OUTLETS="cn123:7 cn124:8"   # node:outlet pairs
#
#  (B) Site command hook: set WMSbench_PDU_CMD to a command that prints watts for a
#      node argument. Site-specific administrator tooling can be wrapped here.
#        export WMSbench_PDU_CMD='my-pdu-tool --watts --node'   # invoked: $WMSbench_PDU_CMD cn123
#
# As the HPC admin you have direct PDU access (no intermediary); this wrapper
# just standardizes the output so ``analysis/plot_energy.py`` can consume it.
#
# usage: pdu_sampler.sh <out_csv> <duration_seconds> [interval_seconds]
# CSV columns: ts_unix,node,watts
set -euo pipefail

OUT=${1:?usage: $0 <out_csv> <duration_seconds> [interval]}
DURATION=${2:?usage: $0 <out_csv> <duration_seconds> [interval]}
INTERVAL=${3:-10}

[ -f "$OUT" ] || echo "ts_unix,node,watts" > "$OUT"

read_snmp() {  # node outlet -> watts
    local node=$1 outlet=$2
    local oid=${WMSbench_PDU_OID_TEMPLATE/\{OUTLET\}/$outlet}
    snmpget -v2c -c "${WMSbench_PDU_COMMUNITY:?set WMSbench_PDU_COMMUNITY}" \
        -Ovq "$WMSbench_PDU_HOST" "$oid" 2>/dev/null | tr -d ' '
}

read_cmd() {   # node -> watts, via site hook
    local node=$1
    $WMSbench_PDU_CMD "$node" 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+)?' | head -1
}

END=$(( $(date +%s) + DURATION ))
while [ "$(date +%s)" -lt "$END" ]; do
    TS=$(date +%s)
    if [ -n "${WMSbench_PDU_CMD:-}" ]; then
        for node in ${WMSbench_PDU_NODES:?set WMSbench_PDU_NODES="cn123 cn124"}; do
            w=$(read_cmd "$node"); [ -n "$w" ] && echo "${TS},${node},${w}" >> "$OUT"
        done
    elif [ -n "${WMSbench_PDU_HOST:-}" ]; then
        for pair in ${WMSbench_PDU_OUTLETS:?set WMSbench_PDU_OUTLETS="cn123:7 cn124:8"}; do
            node=${pair%%:*}; outlet=${pair##*:}
            w=$(read_snmp "$node" "$outlet"); [ -n "$w" ] && echo "${TS},${node},${w}" >> "$OUT"
        done
    else
        echo "configure WMSbench_PDU_CMD or WMSbench_PDU_HOST (see header)" >&2; exit 2
    fi
    sleep "$INTERVAL"
done

#!/usr/bin/env bash
set -euo pipefail

wftune_bootstrap_failure() {
    local rc=$? tmp
    trap - EXIT
    if [[ -n ${WMSbench_HANDOFF_DIR:-} && -d $WMSbench_HANDOFF_DIR ]]; then
        tmp=$(mktemp "$WMSbench_HANDOFF_DIR/.wrapper_failed.XXXXXX") || exit "$rc"
        printf '%s\n' 'schema_version=1' "exit_code=$rc" \
            "failed_epoch=$(date +%s.%N)" 'stage=before_common_helper' >"$tmp"
        mv "$tmp" "$WMSbench_HANDOFF_DIR/wrapper_failed.env"
    fi
    exit "$rc"
}
trap wftune_bootstrap_failure EXIT
source "${WMSbench_HARNESS_ROOT:?}/examples/snakemake_job_common.sh" jobarray

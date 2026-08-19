#!/usr/bin/env bash
# Shared body for Snakemake batch adapters.
#
# This adapter intentionally owns no pipeline-specific paths, targets, profiles,
# resources, or executor options.  They are sourced from
# WMSbench_PIPELINE_ENV_FILE, whose hash is frozen into every run record.
set -euo pipefail

WMSbench_BACKEND_EXPECTED=${1:?snakemake_job_common.sh requires a backend name}
readonly WMSbench_BACKEND_EXPECTED

controller_required=(
    WMSbench_VENUE WMSbench_REP WMSbench_BACKEND WMSbench_WMS
    WMSbench_HARNESS_ROOT WMSbench_PIPELINE_RUN_DIR WMSbench_MONITOR_RUN_DIR
    WMSbench_HANDOFF_DIR WMSbench_PIPELINE_ENV_FILE WMSbench_ACCOUNT
    WMSbench_PARTITION WMSbench_NODE_CONSTRAINT
)
for name in "${controller_required[@]}"; do
    [[ -n ${!name:-} ]] || {
        echo "controller handoff variable is unset: $name" >&2
        exit 2
    }
done
[[ $WMSbench_WMS == snakemake ]] || {
    echo "Snakemake wrapper received WMSbench_WMS=$WMSbench_WMS" >&2
    exit 2
}
[[ $WMSbench_BACKEND == "$WMSbench_BACKEND_EXPECTED" ]] || {
    echo "backend mismatch: expected=$WMSbench_BACKEND_EXPECTED actual=$WMSbench_BACKEND" >&2
    exit 2
}
case "$WMSbench_BACKEND" in
    native|jobarray) ;;
    *) echo "the bundled Snakemake adapter supports native and jobarray" >&2; exit 2 ;;
esac
[[ $WMSbench_REP =~ ^[1-9][0-9]*$ ]] || {
    echo "WMSbench_REP must be a positive block index" >&2
    exit 2
}
[[ -n ${SLURM_JOB_ID:-} ]] || {
    echo "the Snakemake driver must run inside the controller-submitted allocation" >&2
    exit 2
}

case "$WMSbench_HANDOFF_DIR/" in
    "$WMSbench_PIPELINE_RUN_DIR"/*)
        echo "handoff directory must not be inside the pipeline run directory" >&2
        exit 2
        ;;
esac
mkdir -p "$WMSbench_PIPELINE_RUN_DIR" "$WMSbench_HANDOFF_DIR"
if [[ -e $WMSbench_HANDOFF_DIR/started.env || -e $WMSbench_HANDOFF_DIR/finished.env ]]; then
    echo "handoff markers already exist; refusing to reuse a trial directory" >&2
    exit 2
fi

atomic_write() {
    local destination=$1
    shift
    local tmp
    tmp=$(mktemp "$WMSbench_HANDOFF_DIR/.$(basename "$destination").XXXXXX")
    printf '%s\n' "$@" >"$tmp"
    mv "$tmp" "$destination"
}

copy_run_artifact() {
    local source=$1 name=$2 tmp
    [[ -f $source && ! -L $source && -s $source ]] || {
        echo "completed workflow artifact is missing or empty: $source" >&2
        return 1
    }
    tmp=$(mktemp "$WMSbench_MONITOR_RUN_DIR/.$name.XXXXXX") || return
    cp "$source" "$tmp" || { rm -f "$tmp"; return 1; }
    chmod 0640 "$tmp"
    mv "$tmp" "$WMSbench_MONITOR_RUN_DIR/$name"
}

TRACE_FILE="$WMSbench_PIPELINE_RUN_DIR/trace/trace.txt"
REPORT_FILE="$WMSbench_PIPELINE_RUN_DIR/report/report.html"
STARTED_EPOCH=$(date +%s.%N)
atomic_write "$WMSbench_HANDOFF_DIR/started.env" \
    'schema_version=1' \
    "venue=$WMSbench_VENUE" \
    "rep=$WMSbench_REP" \
    "backend=$WMSbench_BACKEND" \
    'wms=snakemake' \
    "main_job_id=$SLURM_JOB_ID" \
    "started_epoch=$STARTED_EPOCH" \
    "hostname=$(hostname)" \
    "slurm_partition=${SLURM_JOB_PARTITION:-}" \
    "slurm_nodelist=${SLURM_JOB_NODELIST:-}" \
    "slurm_num_nodes=${SLURM_JOB_NUM_NODES:-}" \
    "slurm_cpus_on_node=${SLURM_CPUS_ON_NODE:-}"
atomic_write "$WMSbench_HANDOFF_DIR/trace_path.txt" "$TRACE_FILE"

PIPELINE_EXIT_CODE=125
LOG_DIR=
finish_handoff() {
    local shell_rc=$?
    trap - EXIT INT TERM
    set +e
    if (( PIPELINE_EXIT_CODE == 125 )); then
        PIPELINE_EXIT_CODE=$shell_rc
    fi
    local state=failed
    (( PIPELINE_EXIT_CODE == 0 )) && state=completed
    local trace_copy_rc=1 report_copy_rc=1
    if (( PIPELINE_EXIT_CODE == 0 )); then
        copy_run_artifact "$TRACE_FILE" trace.txt
        trace_copy_rc=$?
        copy_run_artifact "$REPORT_FILE" report.html
        report_copy_rc=$?
        if (( trace_copy_rc != 0 || report_copy_rc != 0 )); then
            PIPELINE_EXIT_CODE=74
            state=failed
        fi
    elif [[ -n $LOG_DIR ]]; then
        [[ ! -s $LOG_DIR/pipeline.stderr ]] \
            || copy_run_artifact "$LOG_DIR/pipeline.stderr" failure-pipeline.stderr
        [[ ! -s $LOG_DIR/snakemake.log ]] \
            || copy_run_artifact "$LOG_DIR/snakemake.log" failure-snakemake.log
    fi
    atomic_write "$WMSbench_HANDOFF_DIR/finished.env" \
        'schema_version=1' \
        "venue=$WMSbench_VENUE" \
        "rep=$WMSbench_REP" \
        "backend=$WMSbench_BACKEND" \
        'wms=snakemake' \
        "main_job_id=$SLURM_JOB_ID" \
        "state=$state" \
        "pipeline_exit_code=$PIPELINE_EXIT_CODE" \
        'teardown_exit_code=0' \
        "finished_epoch=$(date +%s.%N)" \
        "trace_path=$TRACE_FILE"
    exit "$PIPELINE_EXIT_CODE"
}
trap finish_handoff EXIT
trap 'PIPELINE_EXIT_CODE=130; exit 130' INT
trap 'PIPELINE_EXIT_CODE=143; exit 143' TERM

# Preserve controller-owned identity, path, and placement values across the
# benchmark-user configuration file.
CONTROLLER_VENUE=$WMSbench_VENUE
CONTROLLER_REP=$WMSbench_REP
CONTROLLER_BACKEND=$WMSbench_BACKEND
CONTROLLER_WMS=$WMSbench_WMS
CONTROLLER_HARNESS_ROOT=$WMSbench_HARNESS_ROOT
CONTROLLER_PIPELINE_RUN_DIR=$WMSbench_PIPELINE_RUN_DIR
CONTROLLER_MONITOR_RUN_DIR=$WMSbench_MONITOR_RUN_DIR
CONTROLLER_HANDOFF_DIR=$WMSbench_HANDOFF_DIR
CONTROLLER_PIPELINE_ENV_FILE=$WMSbench_PIPELINE_ENV_FILE
CONTROLLER_ACCOUNT=$WMSbench_ACCOUNT
CONTROLLER_PARTITION=$WMSbench_PARTITION
CONTROLLER_QOS=${WMSbench_QOS:-}
CONTROLLER_NODE_CONSTRAINT=$WMSbench_NODE_CONSTRAINT

# shellcheck source=/dev/null
source "$WMSbench_PIPELINE_ENV_FILE"
WMSbench_VENUE=$CONTROLLER_VENUE
WMSbench_REP=$CONTROLLER_REP
WMSbench_BACKEND=$CONTROLLER_BACKEND
WMSbench_WMS=$CONTROLLER_WMS
WMSbench_HARNESS_ROOT=$CONTROLLER_HARNESS_ROOT
WMSbench_PIPELINE_RUN_DIR=$CONTROLLER_PIPELINE_RUN_DIR
WMSbench_MONITOR_RUN_DIR=$CONTROLLER_MONITOR_RUN_DIR
WMSbench_HANDOFF_DIR=$CONTROLLER_HANDOFF_DIR
WMSbench_PIPELINE_ENV_FILE=$CONTROLLER_PIPELINE_ENV_FILE
WMSbench_ACCOUNT=$CONTROLLER_ACCOUNT
WMSbench_PARTITION=$CONTROLLER_PARTITION
WMSbench_QOS=$CONTROLLER_QOS
WMSbench_NODE_CONSTRAINT=$CONTROLLER_NODE_CONSTRAINT
export WMSbench_VENUE WMSbench_REP WMSbench_BACKEND WMSbench_WMS
export WMSbench_HARNESS_ROOT WMSbench_PIPELINE_RUN_DIR WMSbench_MONITOR_RUN_DIR
export WMSbench_HANDOFF_DIR WMSbench_PIPELINE_ENV_FILE WMSbench_ACCOUNT
export WMSbench_PARTITION WMSbench_QOS WMSbench_NODE_CONSTRAINT

pipeline_required=(
    WMSbench_PIPELINE WMSbench_PIPELINE_REVISION WMSbench_SNAKEFILE
    WMSbench_SNAKEMAKE_PROFILE
    WMSbench_SNAKEMAKE_CONFIGFILE WMSbench_SNAKEMAKE_JOBS
    WMSbench_INPUT_MANIFEST WMSbench_PIPELINE_SOURCE_MANIFEST
    WMSbench_CONTAINER_DIGEST WMSbench_PHYSICAL_NODE_CPUS
    WMSbench_PHYSICAL_NODE_MEMORY WMSbench_ALLOCATION_CPUS
    WMSbench_LOCAL_CPUS WMSbench_NODE_MEMORY WMSbench_BULK_NODES
    WMSbench_ARRAY_SIZE WMSbench_SLURM_QUEUE_SIZE WMSbench_HQ_WORKERS
    WMSbench_HQ_WORKER_CPUS WMSbench_FLUX_NODES
)
for name in "${pipeline_required[@]}"; do
    [[ -n ${!name:-} ]] || { echo "Snakemake variable is unset: $name" >&2; exit 2; }
done
if ! declare -p WMSbench_SNAKEMAKE_COMMAND >/dev/null 2>&1 \
        || [[ $(declare -p WMSbench_SNAKEMAKE_COMMAND 2>/dev/null) != 'declare -a '* ]] \
        || (( ${#WMSbench_SNAKEMAKE_COMMAND[@]} == 0 )); then
    echo "WMSbench_SNAKEMAKE_COMMAND must be a non-empty Bash array" >&2
    exit 2
fi
declare -p WMSbench_SNAKEMAKE_SET_RESOURCES >/dev/null 2>&1 \
    || WMSbench_SNAKEMAKE_SET_RESOURCES=()
declare -p WMSbench_SNAKEMAKE_SET_THREADS >/dev/null 2>&1 \
    || WMSbench_SNAKEMAKE_SET_THREADS=()
for args_name in WMSbench_SNAKEMAKE_COMMON_ARGS \
        WMSbench_SNAKEMAKE_NATIVE_ARGS WMSbench_SNAKEMAKE_JOBARRAY_ARGS \
        WMSbench_SNAKEMAKE_DEFAULT_RESOURCES WMSbench_SNAKEMAKE_SET_RESOURCES \
        WMSbench_SNAKEMAKE_SET_THREADS; do
    if declare -p "$args_name" >/dev/null 2>&1; then
        [[ $(declare -p "$args_name") == 'declare -a '* ]] || {
            echo "$args_name must be a Bash array" >&2
            exit 2
        }
        declare -n args_ref="$args_name"
        for argument in "${args_ref[@]}"; do
            case "$argument" in
                --snakefile|--snakefile=*|--directory|--directory=*|\
                --profile|--profile=*|--workflow-profile|--workflow-profile=*|\
                --configfile|--configfile=*|--executor|--executor=*|\
                --jobs|--jobs=*|-j|-j=*|--slurm-array-jobs|\
                --slurm-array-jobs=*|--slurm-array-limit|--slurm-array-limit=*|\
                --default-resources|--default-resources=*|--set-resources|\
                --set-resources=*|--set-threads|--set-threads=*|\
                --slurm-qos|--slurm-qos=*)
                    echo "$args_name cannot override harness lifecycle/treatment option: $argument" >&2
                    exit 2
                    ;;
            esac
        done
        unset -n args_ref
    fi
done
if ! declare -p WMSbench_SNAKEMAKE_DEFAULT_RESOURCES >/dev/null 2>&1 \
        || (( ${#WMSbench_SNAKEMAKE_DEFAULT_RESOURCES[@]} == 0 )); then
    echo "WMSbench_SNAKEMAKE_DEFAULT_RESOURCES must be a non-empty Bash array" >&2
    exit 2
fi
seen_account=0
seen_partition=0
seen_constraint=0
for resource in "${WMSbench_SNAKEMAKE_DEFAULT_RESOURCES[@]}"; do
    case "$resource" in
        slurm_account=*)
            [[ $resource == "slurm_account=$WMSbench_ACCOUNT" ]] || {
                echo "Snakemake slurm_account differs from the controller contract" >&2
                exit 2
            }
            seen_account=$((seen_account + 1))
            ;;
        slurm_partition=*)
            [[ $resource == "slurm_partition=$WMSbench_PARTITION" ]] || {
                echo "Snakemake slurm_partition differs from the controller contract" >&2
                exit 2
            }
            seen_partition=$((seen_partition + 1))
            ;;
        constraint=*)
            [[ $WMSbench_NODE_CONSTRAINT != none \
                    && $resource == "constraint=$WMSbench_NODE_CONSTRAINT" ]] || {
                echo "Snakemake constraint differs from the controller contract" >&2
                exit 2
            }
            seen_constraint=$((seen_constraint + 1))
            ;;
    esac
done
(( seen_account == 1 && seen_partition == 1 )) || {
    echo "Snakemake default resources must declare the controller account and partition exactly once" >&2
    exit 2
}
if [[ $WMSbench_NODE_CONSTRAINT == none ]]; then
    (( seen_constraint == 0 )) || {
        echo "Snakemake default resources must omit constraint when controller constraint is none" >&2
        exit 2
    }
else
    (( seen_constraint == 1 )) || {
        echo "Snakemake default resources must declare the controller constraint exactly once" >&2
        exit 2
    }
fi
for resource in "${WMSbench_SNAKEMAKE_SET_RESOURCES[@]}"; do
    case "$resource" in
        *:slurm_account=*|*:slurm_partition=*|*:constraint=*)
            echo "rule-level placement override is forbidden by the common Slurm contract: $resource" >&2
            exit 2
            ;;
    esac
done
if declare -p WMSbench_SNAKEMAKE_TARGETS >/dev/null 2>&1 \
        && [[ $(declare -p WMSbench_SNAKEMAKE_TARGETS) != 'declare -a '* ]]; then
    echo "WMSbench_SNAKEMAKE_TARGETS must be a Bash array" >&2
    exit 2
fi
for name in WMSbench_PHYSICAL_NODE_CPUS WMSbench_ALLOCATION_CPUS \
            WMSbench_LOCAL_CPUS WMSbench_BULK_NODES WMSbench_ARRAY_SIZE \
            WMSbench_SLURM_QUEUE_SIZE WMSbench_HQ_WORKERS \
            WMSbench_HQ_WORKER_CPUS WMSbench_FLUX_NODES \
            WMSbench_SNAKEMAKE_JOBS; do
    [[ ${!name} =~ ^[1-9][0-9]*$ ]] || {
        echo "$name must be a positive integer" >&2
        exit 2
    }
done
if [[ $WMSbench_BACKEND == jobarray ]]; then
    [[ -n ${WMSbench_SNAKEMAKE_ARRAY_RULES:-} ]] || {
        echo "WMSbench_SNAKEMAKE_ARRAY_RULES is required for jobarray" >&2
        exit 2
    }
fi
[[ $WMSbench_CONTAINER_DIGEST =~ ^sha256:[0-9A-Fa-f]{64}$ ]] || {
    echo "WMSbench_CONTAINER_DIGEST must be sha256:<64 hex digits>" >&2
    exit 2
}

for required_file in "$WMSbench_SNAKEFILE" "$WMSbench_SNAKEMAKE_PROFILE" \
        "$WMSbench_SNAKEMAKE_CONFIGFILE" "$WMSbench_INPUT_MANIFEST" \
        "$WMSbench_PIPELINE_SOURCE_MANIFEST"; do
    [[ $required_file == /* && -f $required_file ]] || {
        echo "frozen Snakemake contract file is missing or non-absolute: $required_file" >&2
        exit 2
    }
done
if grep -Eq '^[[:space:]]*slurm[-_]array[-_]jobs[[:space:]]*:' \
        "$WMSbench_SNAKEMAKE_PROFILE"; then
    echo "the shared site profile must not set slurm-array-jobs; the backend adapter owns that treatment" >&2
    exit 2
fi
if [[ -n ${WMSbench_SNAKEMAKE_WORKFLOW_PROFILE:-} ]]; then
    [[ $WMSbench_SNAKEMAKE_WORKFLOW_PROFILE == /* \
            && -f $WMSbench_SNAKEMAKE_WORKFLOW_PROFILE ]] || {
        echo "WMSbench_SNAKEMAKE_WORKFLOW_PROFILE must be an absolute file or empty" >&2
        exit 2
    }
fi
for profile_file in "$WMSbench_SNAKEMAKE_PROFILE" \
        "${WMSbench_SNAKEMAKE_WORKFLOW_PROFILE:-}"; do
    [[ -n $profile_file ]] || continue
    if grep -Eq '(slurm_account|slurm_partition|^[[:space:]]*constraint[[:space:]]*:)' \
            "$profile_file"; then
        echo "profile must not override account/partition/constraint; declare them in WMSbench_SNAKEMAKE_DEFAULT_RESOURCES: $profile_file" >&2
        exit 2
    fi
done

RESULTS_DIR="$WMSbench_PIPELINE_RUN_DIR/results"
WORK_DIR="$WMSbench_PIPELINE_RUN_DIR/workspace"
LOG_DIR="$WMSbench_PIPELINE_RUN_DIR/logs"
TRACE_DIR="$WMSbench_PIPELINE_RUN_DIR/trace"
REPORT_DIR="$WMSbench_PIPELINE_RUN_DIR/report"
mkdir -p "$RESULTS_DIR" "$WORK_DIR" "$LOG_DIR" "$TRACE_DIR" "$REPORT_DIR"
[[ ! -e $TRACE_FILE ]] || {
    echo "trace already exists; cold trial directory is not empty: $TRACE_FILE" >&2
    exit 2
}
exec >>"$LOG_DIR/pipeline.stdout" 2>>"$LOG_DIR/pipeline.stderr"

WMSbench_MODULE_LIST=
if declare -p WMSbench_MODULES >/dev/null 2>&1 && (( ${#WMSbench_MODULES[@]} )); then
    WMSbench_MODULE_LIST="${WMSbench_MODULES[*]}"
    [[ -r ${WMSbench_MODULE_INIT:-} ]] || {
        echo "WMSbench_MODULE_INIT must name a readable module init script" >&2
        exit 2
    }
    set +eu
    # shellcheck source=/dev/null
    source "$WMSbench_MODULE_INIT"
    set -eu
    module load "${WMSbench_MODULES[@]}"
    module list || true
fi
export WMSbench_MODULE_LIST

hash_file() {
    local path=$1
    [[ $path == /* && -f $path ]] || {
        echo "cannot hash missing/non-absolute contract file: $path" >&2
        exit 2
    }
    sha256sum "$path" | awk '{print $1}'
}

PIPELINE_ENV_SHA256=$(hash_file "$WMSbench_PIPELINE_ENV_FILE")
CONFIG_SHA256=$(hash_file "$WMSbench_SNAKEMAKE_CONFIGFILE")
PROFILE_SHA256=$(hash_file "$WMSbench_SNAKEMAKE_PROFILE")
if [[ -n ${WMSbench_SNAKEMAKE_WORKFLOW_PROFILE:-} ]]; then
    WORKFLOW_PROFILE_SHA256=$(hash_file "$WMSbench_SNAKEMAKE_WORKFLOW_PROFILE")
else
    WORKFLOW_PROFILE_SHA256=$PROFILE_SHA256
fi
INPUT_MANIFEST_SHA256=$(hash_file "$WMSbench_INPUT_MANIFEST")
PIPELINE_SOURCE_MANIFEST_SHA256=$(hash_file "$WMSbench_PIPELINE_SOURCE_MANIFEST")
TRACE_ADAPTER_SHA256=$(hash_file "$WMSbench_HARNESS_ROOT/examples/snakemake_job_common.sh")

EXECUTOR_VARIABLE="WMSbench_SNAKEMAKE_EXECUTOR_${WMSbench_BACKEND^^}"
SNAKEMAKE_EXECUTOR=${!EXECUTOR_VARIABLE:-}
[[ -n $SNAKEMAKE_EXECUTOR ]] || {
    echo "$EXECUTOR_VARIABLE is required" >&2
    exit 2
}
[[ $SNAKEMAKE_EXECUTOR =~ ^[A-Za-z0-9_.-]+$ ]] || {
    echo "$EXECUTOR_VARIABLE contains an unsafe executor name" >&2
    exit 2
}

atomic_write "$WMSbench_HANDOFF_DIR/pipeline_contract.env" \
    'schema_version=1' \
    'wms=snakemake' \
    "pipeline=$WMSbench_PIPELINE" \
    "pipeline_revision=$WMSbench_PIPELINE_REVISION" \
    "nf_profile=snakemake:$WMSbench_SNAKEMAKE_PROFILE" \
    "container_digest=$WMSbench_CONTAINER_DIGEST" \
    "params_sha256=$CONFIG_SHA256" \
    "pipeline_env_sha256=$PIPELINE_ENV_SHA256" \
    "common_config_sha256=$PROFILE_SHA256" \
    "stage_config_sha256=$WORKFLOW_PROFILE_SHA256" \
    "slurm_policy_config_sha256=$PROFILE_SHA256" \
    "trace_config_sha256=$TRACE_ADAPTER_SHA256" \
    "input_manifest_sha256=$INPUT_MANIFEST_SHA256" \
    "pipeline_source_manifest_sha256=$PIPELINE_SOURCE_MANIFEST_SHA256" \
    "backend_config_sha256=$PROFILE_SHA256" \
    "physical_node_cpus=$WMSbench_PHYSICAL_NODE_CPUS" \
    "physical_node_memory=$WMSbench_PHYSICAL_NODE_MEMORY" \
    "allocation_cpus=$WMSbench_ALLOCATION_CPUS" \
    "local_cpus=$WMSbench_LOCAL_CPUS" \
    "node_cpus=$WMSbench_LOCAL_CPUS" \
    "node_memory=$WMSbench_NODE_MEMORY" \
    "bulk_nodes=$WMSbench_BULK_NODES" \
    "array_size=$WMSbench_ARRAY_SIZE" \
    "slurm_queue_size=$WMSbench_SLURM_QUEUE_SIZE" \
    "hq_workers=$WMSbench_HQ_WORKERS" \
    "hq_worker_cpus=$WMSbench_HQ_WORKER_CPUS" \
    "flux_nodes=$WMSbench_FLUX_NODES" \
    "modules=$WMSbench_MODULE_LIST" \
    "module_init=${WMSbench_MODULE_INIT:-}" \
    "snakemake_executor=$SNAKEMAKE_EXECUTOR" \
    "snakemake_array_rules=${WMSbench_SNAKEMAKE_ARRAY_RULES:-disabled}"

SNAKEMAKE_CMD=("${WMSbench_SNAKEMAKE_COMMAND[@]}")
command -v "${SNAKEMAKE_CMD[0]}" >/dev/null 2>&1 || {
    echo "snakemake is not on PATH; check WMSbench_MODULES or WMSbench_SNAKEMAKE_COMMAND" >&2
    exit 2
}

SNAKEMAKE_ARGS=(
    --snakefile "$WMSbench_SNAKEFILE"
    --directory "$WORK_DIR"
    --profile "$WMSbench_SNAKEMAKE_PROFILE"
    --configfile "$WMSbench_SNAKEMAKE_CONFIGFILE"
    --executor "$SNAKEMAKE_EXECUTOR"
    --jobs "$WMSbench_SNAKEMAKE_JOBS"
    --default-resources "${WMSbench_SNAKEMAKE_DEFAULT_RESOURCES[@]}"
)
[[ -z $WMSbench_QOS ]] || SNAKEMAKE_ARGS+=(--slurm-qos "$WMSbench_QOS")
[[ -z ${WMSbench_SNAKEMAKE_WORKFLOW_PROFILE:-} ]] \
    || SNAKEMAKE_ARGS+=(--workflow-profile "$WMSbench_SNAKEMAKE_WORKFLOW_PROFILE")
if [[ $WMSbench_BACKEND == jobarray ]]; then
    SNAKEMAKE_ARGS+=(
        --slurm-array-jobs "$WMSbench_SNAKEMAKE_ARRAY_RULES"
        --slurm-array-limit "$WMSbench_ARRAY_SIZE"
    )
fi
if declare -p WMSbench_SNAKEMAKE_COMMON_ARGS >/dev/null 2>&1; then
    SNAKEMAKE_ARGS+=("${WMSbench_SNAKEMAKE_COMMON_ARGS[@]}")
fi
if (( ${#WMSbench_SNAKEMAKE_SET_RESOURCES[@]} )); then
    SNAKEMAKE_ARGS+=(--set-resources "${WMSbench_SNAKEMAKE_SET_RESOURCES[@]}")
fi
if (( ${#WMSbench_SNAKEMAKE_SET_THREADS[@]} )); then
    SNAKEMAKE_ARGS+=(--set-threads "${WMSbench_SNAKEMAKE_SET_THREADS[@]}")
fi
BACKEND_ARGS_NAME="WMSbench_SNAKEMAKE_${WMSbench_BACKEND^^}_ARGS"
if declare -p "$BACKEND_ARGS_NAME" >/dev/null 2>&1; then
    declare -n BACKEND_ARGS_REF="$BACKEND_ARGS_NAME"
    SNAKEMAKE_ARGS+=("${BACKEND_ARGS_REF[@]}")
fi
if declare -p WMSbench_SNAKEMAKE_TARGETS >/dev/null 2>&1; then
    SNAKEMAKE_ARGS+=("${WMSbench_SNAKEMAKE_TARGETS[@]}")
fi

{
    printf 'wms=snakemake\nbackend=%s\nexecutor=%s\ncommand=' \
        "$WMSbench_BACKEND" "$SNAKEMAKE_EXECUTOR"
    printf '%q ' "${SNAKEMAKE_CMD[@]}" "${SNAKEMAKE_ARGS[@]}"
    printf '\n'
} >"$LOG_DIR/command.env"

WORKFLOW_START_EPOCH=$(date +%s.%N)
set +e
"${SNAKEMAKE_CMD[@]}" "${SNAKEMAKE_ARGS[@]}" \
    >"$LOG_DIR/snakemake.log" 2>&1
PIPELINE_EXIT_CODE=$?
set -e
WORKFLOW_FINISH_EPOCH=$(date +%s.%N)

if (( PIPELINE_EXIT_CODE == 0 )); then
    # Snakemake does not expose a stable cross-version per-job trace format.
    # This truthful workflow-level row supplies the common clean-start endpoint;
    # raw Snakemake logs and the semantic validator remain the correctness
    # evidence. Cross-WMS comparisons therefore report total, not per-task, RPC.
    printf 'process\tstatus\texit\tsubmit\tstart\tcomplete\tnative_id\tname\n' \
        >"$TRACE_FILE"
    printf 'WORKFLOW\tCOMPLETED\t0\t%s\t%s\t%s\t\tworkflow\n' \
        "$WORKFLOW_START_EPOCH" "$WORKFLOW_START_EPOCH" \
        "$WORKFLOW_FINISH_EPOCH" >>"$TRACE_FILE"
    printf '%s\n' \
        '<!doctype html><html><head><meta charset="utf-8"><title>Snakemake benchmark run</title></head>' \
        '<body><h1>Snakemake benchmark run completed</h1>' \
        '<p>The immutable command, raw Snakemake log, normalized workflow trace, manifests, and semantic-validation output are retained with this run.</p>' \
        '</body></html>' >"$REPORT_FILE"
fi
exit "$PIPELINE_EXIT_CODE"

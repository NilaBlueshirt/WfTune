# Nextflow configuration and DSL2 fragments

Copyable fragments for P5 to P8 of Mu, Dizon, Otero, and Battelle, "Ten
Practices for Refactoring Scientific Pipelines to nf-core DSL2 on Shared Slurm
HPC" (USRSE'26). The shapes follow the released pipeline at
https://github.com/NilaBlueshirt/make_lastz_chains (branch `nf-core-refactor`).

Placeholder convention. Every token written as `<<SITE_SOMETHING>>` is a
site-specific value to be set from the site's limits (Section 2 of SKILL.md).
A Nextflow config containing one of these tokens will not parse, which is
intended: the pipeline cannot run with a placeholder left in. Inside a shell
fragment a `<<...>>` token reads to bash as a heredoc, so substitute every
placeholder before running `bash -n`. Values quoted with the comment
"case-study value" are what the paper reports for one pipeline at one site;
treat them as starting points to re-tune, not as recommendations. Process
names (`LASTZ`, `AXT_CHAIN`, `REPEAT_FILLER`, `EXTRACT_CHROMS`) are from the
case study; substitute your own. Where a listing is marked as the paper's, the
quoted lines are the paper's and the surrounding scaffolding is this file's.

## 1. Strict-by-default errorStrategy with maxRetries (P7, layer 1)

```groovy
// nextflow.config. Adapted from the paper's two-line listing (process scope
// and comments added here).
process {
    errorStrategy = 'retry'
    maxRetries    = 8        // case-study value; the one place the retry budget is stated
}
```

Why it is written this way: the retry limit is specified once, and a task that
continues to fail beyond it fails the run. `maxErrors` defaults to unlimited
(-1) and bounds total failures across a process; it is not a tolerance knob,
and leaving it unlimited does not change what happens when one task exhausts
`maxRetries` (Nextflow terminates the run). What hides failures is
`errorStrategy = 'ignore'`, or `'finish'` or `'retry'` chosen on the wrong exit
codes. A finite `maxErrors` on a many-task process (for example 25) is a
waste bound: a systematic failure then aborts after a bounded number of
attempts instead of retrying every task eight times. Use `maxRetries = 1`
under the `dev` profile (Section 4). The case-study value 8 reflects transient
Slurm failures at that site; re-tune it from the failure classes observed in
`trace.txt`.

An equivalent explicit form (not in the paper; from the repository's change
log, verify there before quoting):

```groovy
process {
    errorStrategy = { task.attempt <= 8 ? 'retry' : 'terminate' }
    maxRetries    = 8
}
```

In Nextflow 24.x both forms end the run once a task's retries are exhausted
(`TaskProcessor.checkErrorStrategy` returns TERMINATE when the retry condition
fails). The pipeline's change log attributes a silent loss to the plain form;
the paper attributes Bug 1 to wrappers that ignored return codes (P10).
Confirm the behavior on your version with the Step 10 injected-failure test.

Pair the retry with resource scaling that is capped (Section 2 below), so a
retry asks for more memory or time without being rejected at submission.

## 2. Resource tiers with dynamic scaling and caps (P6, items 1 and 4)

```groovy
// nextflow.config. Ceilings are infrastructure, so they live here and not in
// params.json. Read them from `scontrol show partition`. resourceLimits needs
// Nextflow 24.04 or later, which process.array (Section 3) needs anyway.
process {
    resourceLimits = [ cpus: <<SITE_MAX_CPUS>>, memory: '<<SITE_MAX_MEMORY>>', time: '<<SITE_MAX_TIME>>' ]

    // Base values are placeholders: set each tier from sacct on a legacy run or
    // from report.html of a representative run (P6 item 1), so per-task jobs
    // fit backfill windows. task.attempt scales the request on retry and
    // resourceLimits caps it (item 4).
    withLabel: process_fast {        // the released pipeline's label for its many-task tier; the paper
                                     // names only nf-core's process_low/medium/high and a 2 h routing rule
        cpus   = 1
        memory = { <<SITE_FAST_MEM>>.GB * task.attempt }
        time   = { <<SITE_FAST_TIME>>.h * task.attempt }
    }
    withLabel: process_low {
        cpus   = <<SITE_LOW_CPUS>>
        memory = { <<SITE_LOW_MEM>>.GB * task.attempt }
        time   = { <<SITE_LOW_TIME>>.h * task.attempt }
    }
    withLabel: process_medium {
        cpus   = <<SITE_MED_CPUS>>
        memory = { <<SITE_MED_MEM>>.GB * task.attempt }
        time   = { <<SITE_MED_TIME>>.h * task.attempt }
    }
    withLabel: process_high {
        cpus   = <<SITE_HIGH_CPUS>>
        memory = { <<SITE_HIGH_MEM>>.GB * task.attempt }
        time   = { <<SITE_HIGH_TIME>>.h * task.attempt }
    }
    // nf-core modules also carry process_single, process_long, and
    // process_high_memory. Declare them (or map them onto the tiers above) so
    // no module falls through to Nextflow's defaults.
    withLabel: process_single {
        cpus   = 1
        memory = { <<SITE_LOW_MEM>>.GB * task.attempt }
        time   = { <<SITE_LOW_TIME>>.h * task.attempt }
    }
    withLabel: process_long {
        time   = { <<SITE_LONG_TIME>>.h * task.attempt }
    }
    withLabel: process_high_memory {
        memory = { <<SITE_HIGHMEM_MEM>>.GB * task.attempt }
    }
}
```

The case-study pipeline instead uses nf-core's older `check_max()` helper
(`memory = { check_max( 4.GB * task.attempt, 'memory' ) }` against
`params.max_cpus`, `params.max_memory`, and `params.max_time` ceilings), which
is what the paper's P6 item 4 names. Keep it only in a pipeline that already
has it: a `def` function in `nextflow.config` is rejected by Nextflow's strict
configuration parser, and there is no Nextflow version in which
`process.array` works but `resourceLimits` is unavailable. Either approach
satisfies P6 item 4; pick one and apply it to every scaled directive.

## 3. process.array on many-task processes (P6, item 2)

```groovy
// nextflow.config. Requires Nextflow 24.04.0 or later.
process {
    withName: 'LASTZ|AXT_CHAIN|REPEAT_FILLER' {    // the many-task processes
        array = 500    // case-study value; placeholder: keep below the site's MaxArraySize;
                       // the dev profile (Section 4) sets 10 for development runs
    }
}
```

Tasks within one array submission share a base Slurm job ID, which is how the
paper counts distinct `sbatch` submissions. Check the Nextflow documentation
for your version on which directives are restricted inside an array
submission, and keep resource directives uniform within an arrayed process.
First-attempt tasks of one process evaluate the Section 2 closures to the same
values, and Nextflow submits retried tasks (attempt greater than 1)
individually rather than through the array (`TaskArrayCollector.collect()` in
24.10: "submit task directly ... if the task is retried (since it might have
dynamic resources)"), so `task.attempt` scaling and `array` combine. Verify
this in the TaskArrayCollector of your Nextflow version and record the answer
in report item 4. In the case study, arrays substantially reduced submissions
but did not consistently shorten walltime; measure before claiming either
effect.

## 4. Executor settings and the dev profile (P6, item 5)

First example: the case study's values from the paper, with the three values
the paper does not publish left as placeholders.

```groovy
// nextflow.config, inside the slurm profile.
executor {
    name              = 'slurm'
    pollInterval      = '30 sec'   // case-study value: task-monitor tick; reduces polling frequency
    queueStatInterval = '2 min'    // case-study value: queue status poll period against the controller
    exitReadTimeout   = '15 min'   // case-study value: time allowed for .exitcode to become visible
    queueSize         = <<SITE_QUEUE_SIZE>>     // in-flight task cap; at or below the per-user MaxSubmit
    submitRateLimit   = '<<SITE_SUBMIT_RATE>>'  // e.g. '<n>/1min'; keep under what the controller absorbs
    killBatchSize     = <<SITE_KILL_BATCH>>     // cancellations batched per scancel call
}
```

`exitReadTimeout` is how long Nextflow waits for `.exitcode` after a job leaves
the queue before recording the task as failed with an unknown exit status.
Both papers call it a correctness setting: too short, and a finished task
whose exit file is late on a shared filesystem is failed or retried
needlessly; too long, and a genuinely lost task is detected late. Retry fires
when the timeout expires either way. A task that disappears from Slurm without
ever writing `.exitcode` is the watchdog's case (P7 layer 3, Section 8), not
this setting's.

Development profile, usable verbatim, for Step 10 and for every test on a
shared cluster (`nextflow run main.nf -profile apptainer,slurm,dev ...`):

```groovy
// nextflow.config
profiles {
    dev {
        executor.queueSize       = 10
        executor.submitRateLimit = '10/1min'
        process.array            = 10
        process.maxRetries       = 1
    }
}
```

Second example, quoted verbatim from the companion HPCSYSPROS'26 study: its
recommended starting default for the job-array treatment on the Phoenix
cluster, which runs `MaxArraySize=300000` and `MaxJobCount=550000`, measured
on a different workload (4,823 alignment tasks). Do not copy these numbers:
`queueSize` and `killBatchSize` of 10,000 exceed the per-user submit limit on
most university clusters, and Section 1 of SKILL.md forbids guessing site
limits. Read the shape, then set each value from Section 2 of SKILL.md.

```groovy
process {
    executor = 'slurm'
    array    = 500
}
executor {
    name              = 'slurm'
    queueSize         = 10000
    pollInterval      = '10 s'
    queueStatInterval = '1 min'
    submitRateLimit   = '100/1min'
    exitReadTimeout   = '5 min'
    killBatchSize     = 10000
}
```

The two examples differ on every shared setting, which is the point: these are
tuned per site and per campaign, not constants.

## 5. Walltime-based partition routing with withLabel (P6, item 3)

```groovy
// nextflow.config. Bind each tier to the partition whose walltime class fits.
// Case study: tasks of 2 h or less went to a higher-throughput partition,
// longer tiers to the general-purpose partition.
process {
    withLabel: process_fast {
        queue = '<<SITE_SHORT_PARTITION>>'     // walltime limit at or above the tier's capped maximum
    }
    withLabel: 'process_low|process_medium|process_high' {
        queue = '<<SITE_GENERAL_PARTITION>>'
    }
    // Only if the site requires them. A withName clusterOptions replaces (does not
    // append to) this value, so repeat these flags wherever clusterOptions is set.
    clusterOptions = '--account=<<SITE_ACCOUNT>> --qos=<<SITE_QOS>>'
}
```

If a tier's scaled `time` can cross the short partition's limit on retry,
either cap `time` for that tier at the short partition's limit or route on
the scaled value:

```groovy
withLabel: process_fast {
    queue = { task.time <= <<SITE_SHORT_LIMIT>>.h ? '<<SITE_SHORT_PARTITION>>' : '<<SITE_GENERAL_PARTITION>>' }
}
```

The closure evaluates to one partition for every first attempt, and retries
are submitted outside the array (Section 3), so it coexists with `array`.

## 6. Post-stage integrity check (P7, layer 2)

The paper's listing is the `expected_n ... subscribe { }` block; the
surrounding `workflow LASTZ_ALIGNMENT` scaffolding is a sketch of
`subworkflows/local/lastz_alignment/main.nf`, not quoted from the paper. The
check compares the materialized expected pair count with the count of
completion records; `versions.yml` is emitted by every successful task, which
is why its count equals the number of completed tasks.

```groovy
workflow LASTZ_ALIGNMENT {
    take:
    target_parts        // channel: target partitions
    query_parts         // channel: query partitions

    main:
    pair_list = target_parts.combine(query_parts)    // P1: the N x K pairs, natively
    // The Section 9 module takes tuple val(meta), path(target_part), path(query_part),
    // so build the meta map here rather than feeding the bare pair.
    LASTZ(pair_list.map { t, q -> [ [id: "${t.baseName}_${q.baseName}"], t, q ] })

    def expected_n = pair_list.count()
    def actual_n   = LASTZ.out.versions.count()
    expected_n
      .combine(actual_n)
      .subscribe { exp, act ->
        if (exp != act) {
          error "LASTZ integrity check failed: " +
                "expected ${exp} alignment tasks, " +
                "only ${act} completion records."
        }
      }

    emit:
    psl = LASTZ.out.psl
}
```

The check runs when the stage's output channel completes, so it fires at stage
completion, not per task. It catches tasks that never produced a completion
record; a wrapper that falsely reports success still produces one, so it
complements rather than replaces the Step 2 comparison. Test it with a config
that drops one completion record,
`withName: LASTZ { errorStrategy = { task.index == 3 ? 'ignore' : 'retry' } }`,
which must trigger the error.

## 7. Partial-output protection at walltime (P7, layer 4)

The state of the mechanism first. The paper's layer 4 is
`clusterOptions = '--signal=B:USR1@60'` plus a USR1 trap in the task script.
Nextflow's stock task wrapper does not deliver that signal: `.command.run`
(`command-run.txt` in Nextflow 24.10.0, function `nxf_main()`) sets
`trap on_term TERM INT USR2` and `trap '' USR1`. With `B:`, Slurm sends USR1
to the batch shell, which is `.command.run`; it ignores the signal,
`.command.sh` inherits the ignored disposition, and bash refuses to install a
trap for a signal that was ignored on entry, so the handler never runs. Check
your wrapper with `grep USR1 <workdir>/.command.run`. The released pipeline's
change log records no signal trap, so treat this layer as unverified in the
case study.

The released pipeline's `slurm` profile does set
`process.clusterOptions = '--qos=public --signal=USR2@180 ...'`, without `B:`.
The sbatch manual says that without `B:` "all job steps will be signaled, but
not the batch shell itself", and Nextflow's Slurm tasks run inside the batch
shell rather than as `srun` steps, so the wrapper's `trap on_term TERM INT USR2`
handler may never see that signal. If you want an early, clean failure under
the stock wrapper, try `--signal=B:USR2@180`: the wrapper's `on_term` handler
kills the task, `nxf_unstage` skips the outputs of a failed task, and
`on_exit` writes a non-zero `.exitcode` for the retry policy. This reading
comes from the wrapper template, not from a measurement, so confirm it with
the Step 10 gate before relying on it.

What works under the stock wrapper: Slurm's TERM at the time limit reaches
`.command.run`, `on_term` kills the task, and `on_exit` writes a non-zero
`.exitcode`, so the retry policy already sees a walltime kill as an ordinary
failure. The guarantee that no complete-looking partial output exists comes
from writing under a temporary name and moving into place last:

```groovy
// modules/local/lastz/main.nf, script block. Write under a name the output
// glob does not match; mv is the last command, so a kill at any earlier point
// leaves nothing under the declared output name.
script:
def args = task.ext.args ?: ''
"""
lastz ${target_part} ${query_part} ${args} > ${prefix}.psl.partial
mv ${prefix}.psl.partial ${prefix}.psl
"""
```

Option for a site whose wrapper forwards USR1, written as a `shell:` block so
bash variables stay bash variables and `!{...}` marks Nextflow inputs (in a
`script:` block every bash `$` would need escaping as `\$`):

```groovy
// nextflow.config: ask Slurm to send USR1 60 s before the time limit. B: targets
// the batch shell only; without B:, Slurm signals job steps rather than the
// batch shell, so which processes receive it depends on how the tool was
// launched. Test once (Step 10) and record which mechanism produced the failure.
process {
    withName: 'LASTZ|AXT_CHAIN|REPEAT_FILLER' {
        clusterOptions = '--signal=B:USR1@60'   // repeat account/qos flags here if the site needs them
    }
}
```

```groovy
shell:
'''
set -euo pipefail
out="!{prefix}.psl"; tmp="$out.partial"
on_walltime_signal() {
    echo "USR1: walltime nearly exhausted, removing partial output" >&2
    kill "$pid" 2>/dev/null || true
    rm -f "$tmp" "$out"
    exit 140      # inside the 130 to 145 range nf-core's default closure retries;
                  # Section 1's plain 'retry' retries any non-zero exit
}
trap on_walltime_signal USR1
# Run the tool in the background: bash runs a trap only between foreground
# commands, so a foreground tool would delay the handler until it exits.
lastz "!{target_part}" "!{query_part}" !{args} > "$tmp" &
pid=$!
wait "$pid"
mv "$tmp" "$out"
'''
```

Step 10 is the gate: run one task with a deliberately short `time`. If
`.exitcode` is non-zero and no partial file remains, layer 4 is done; record
which mechanism did it (the wrapper's TERM handling, or the trap). If the trap
never fired, record layer 4 as "partial: temporary name plus mv only" and do
not describe it as graceful termination in the report.

## 8. Out-of-band watchdog (P7, layer 3)

Run this on a login node (in `tmux` or `screen`) or as a separate small Slurm
job. Never run it inside the main job: the `scancel` it issues would kill the
watchdog along with the main job. Give the main job a unique `--job-name`
(for example `nf-main-<run id>`): the watchdog matches by name and then checks
the job's `WorkDir`, so a reused name such as the default `nextflow` would be
ambiguous.

```bash
#!/usr/bin/env bash
# nf_watchdog.sh: detect a stalled Nextflow main job and cancel-and-resume it.
set -euo pipefail

NF_RUN_DIR="${NF_RUN_DIR:?directory that holds .nextflow.log}"
NF_MAIN_JOB_NAME="${NF_MAIN_JOB_NAME:?unique --job-name of the main job}"
NF_RESUME_SBATCH="${NF_RESUME_SBATCH:?sbatch script that resubmits with -resume (nf_resume.sbatch below)}"
STALL_THRESHOLD="${STALL_THRESHOLD:-1800}"   # seconds without change; 30 min default (paper);
                                             # keep above executor.dumpInterval (5 min default)
MAX_RESTARTS="${MAX_RESTARTS:-5}"            # cap on cancel-and-resume cycles (paper)
CHECK_INTERVAL="${CHECK_INTERVAL:-300}"      # seconds between checks
WATCH_USER="${USER:-$(id -un)}"              # USER can be unset under set -u in batch environments
LOG="$NF_RUN_DIR/nf_watchdog.log"

log() { printf '%s %s\n' "$(date -Is)" "$*" >>"$LOG"; }

latest_block_hash() {
    # Content-hash the most recent "tasks to be completed: N" block. The main job
    # rewrites this block verbatim while it is stuck, so file mtime is not a
    # signal; the block's content is. The timestamp prefix is stripped so that
    # an identical block hashes identically. Returns 1 when the log is unreadable
    # (wrong NF_RUN_DIR, or the window after a resubmit before Nextflow recreates it).
    [[ -r "$NF_RUN_DIR/.nextflow.log" ]] || return 1
    awk '
        /tasks to be completed:/ { sub(/^.*tasks to be completed:/, "tasks to be completed:"); blk = $0 "\n"; inblk = 1; next }
        inblk && /^(~>|\.\.)/   { blk = blk $0 "\n"; next }
        inblk                   { inblk = 0 }
        END                     { printf "%s", blk }
    ' "$NF_RUN_DIR/.nextflow.log" | md5sum | cut -d" " -f1
}

main_job() {   # prints "<jobid> <state>" for the main job whose WorkDir is NF_RUN_DIR, or nothing
    local jid state
    while read -r jid state; do
        [[ -n "$jid" ]] || continue
        if [[ "$(scontrol show job "$jid" | sed -n 's/.*WorkDir=//p')" == "$NF_RUN_DIR" ]]; then
            printf '%s %s\n' "$jid" "$state"
            return 0
        fi
    done < <(squeue -h -u "$WATCH_USER" -n "$NF_MAIN_JOB_NAME" -o '%i %T')
    return 0
}

restarts=0; last_hash=""; unchanged_since=$(date +%s)
log "watching '$NF_MAIN_JOB_NAME' in $NF_RUN_DIR (threshold ${STALL_THRESHOLD}s, max restarts $MAX_RESTARTS)"
while :; do
    read -r jid state <<<"$(main_job)" || true
    if [[ -z "${jid:-}" ]]; then
        log "main job not in queue; nothing to watch, exiting"
        exit 0
    fi
    if [[ "${state:-}" != "RUNNING" ]]; then
        last_hash=""; unchanged_since=$(date +%s)       # pending or completing is not a stall
    elif ! h=$(latest_block_hash); then
        log "cannot read $NF_RUN_DIR/.nextflow.log; will retry"
    else
        now=$(date +%s)
        if [[ "$h" != "$last_hash" ]]; then
            last_hash=$h; unchanged_since=$now
        elif (( now - unchanged_since >= STALL_THRESHOLD )); then
            if (( restarts >= MAX_RESTARTS )); then
                log "stall detected but MAX_RESTARTS=$MAX_RESTARTS reached; leaving job $jid for a human"
                exit 1
            fi
            log "stall: progress block unchanged for ${STALL_THRESHOLD}s; scancel $jid, then resubmit with -resume"
            scancel "$jid"
            sleep 60                                     # let Slurm finish the cancel first
            sbatch "$NF_RESUME_SBATCH" >>"$LOG" 2>&1
            restarts=$((restarts + 1))
            last_hash=""; unchanged_since=$(date +%s)
        fi
    fi
    sleep "$CHECK_INTERVAL"
done
```

The resubmit script the watchdog needs. It has to carry the same `--job-name`,
change into `NF_RUN_DIR`, and run the same command with `-resume`, or
`main_job()` never finds the resubmission and the watchdog exits with "main
job not in queue":

```bash
#!/usr/bin/env bash
# nf_resume.sbatch
#SBATCH --job-name=<<NF_MAIN_JOB_NAME>>        # the same unique name the watchdog matches
#SBATCH --partition=<<SITE_GENERAL_PARTITION>>
#SBATCH --time=<<MAIN_JOB_WALLTIME>>
#SBATCH --cpus-per-task=<<MAIN_JOB_CPUS>> --mem=<<MAIN_JOB_MEM>>   # the main job is a JVM, not a compute task
cd "<<NF_RUN_DIR>>"
nextflow run main.nf -profile apptainer,slurm -params-file params.json -resume
```

Caveat on the threshold: the block also stays unchanged while a single long
task runs with nothing else in flight, so set `STALL_THRESHOLD` longer than
the longest legitimately quiet interval of the stage you are watching, keep it
above `executor.dumpInterval` (the block is rewritten only that often), or run
the watchdog only around the many-task stages. A false positive costs one
cancel-and-resume (cached tasks are reused; a running long task restarts). For
the Step 10 stall test, run with `STALL_THRESHOLD=120 CHECK_INTERVAL=30` so
the test takes minutes rather than half an hour.

## 9. Dual conda and container directives with an image override (P5)

```groovy
// modules/local/lastz/main.nf: each module declares both.
process LASTZ {
    tag   "${meta.id}"
    label 'process_fast'      // the released pipeline's tier label; see Section 2

    conda     "${moduleDir}/environment.yml"
    container '<<ORG/IMAGE>>@sha256:<<DIGEST>>'   // pin by digest for reproducible runs
    publishDir "${params.outdir}/lastz", mode: 'copy'   // nf-core puts this in conf/modules.config instead

    input:
    tuple val(meta), path(target_part), path(query_part)

    output:
    tuple val(meta), path("*.psl"), emit: psl       // required: no `optional: true` (P10)
    path "versions.yml",            emit: versions  // one record per successful task (P7 layer 2)

    script:
    """
    <<TOOL_COMMAND>>
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        lastz: \$(lastz --version 2>&1 | sed 's/^.*version //')
    END_VERSIONS
    """
}
```

Where the digest comes from: a registry or image query only, never a guess.
`skopeo inspect docker://<<ORG/IMAGE>>:<tag> | jq -r .Digest`,
`docker buildx imagetools inspect <<ORG/IMAGE>>:<tag>`, or the `sha256:` line
that `apptainer pull` prints. If none is reachable, leave `<<DIGEST>>` in place
and list it in report item 4. Pin `environment.yml` and the Dockerfile to the
tool versions the legacy run used (SKILL.md Step 2, item 5); a version change
alters science output and needs its own pre-specified item.

Choose one of the two override forms from the Step 3 audit of tools per
process:

```groovy
// nextflow.config, form (a): the pipeline ships ONE image holding every tool
// (as the case study does). A process-scope container overrides every module's
// container directive, so this one line applies to all processes.
process.container = System.getenv('NXF_CONTAINER_IMAGE') ?: '<<ORG/IMAGE>>@sha256:<<DIGEST>>'
```

```groovy
// Form (b): per-tool images (the nf-core norm). Do NOT set process.container,
// which would route every process into one image and silently break every
// tool that image lacks. Keep the module directives and override per module:
// in nextflow.config
params.container_override = System.getenv('NXF_CONTAINER_IMAGE')
// and in each module
container params.container_override ?: '<<ORG/TOOL_IMAGE>>@sha256:<<DIGEST>>'
// or a withName: block per process in nextflow.config.
```

```groovy
// nextflow.config: runtime profiles.
profiles {
    conda {
        conda.enabled        = true
        apptainer.enabled    = false
        docker.enabled       = false
    }
    apptainer {
        apptainer.enabled    = true
        apptainer.autoMounts = true
        apptainer.cacheDir   = '<<SITE_IMAGE_CACHE>>'   // node-visible cache so tasks do not re-pull
        conda.enabled        = false
    }
    singularity {
        singularity.enabled    = true
        singularity.autoMounts = true
        conda.enabled          = false
    }
    docker {
        docker.enabled = true
        conda.enabled  = false
    }
    slurm {
        process.executor = 'slurm'
        // executor { ... } block from Section 4 goes here
    }
}
```

Usage: `nextflow run main.nf -profile apptainer,slurm -params-file params.json`.
Override: `NXF_CONTAINER_IMAGE=/path/to/local.sif nextflow run ...`. The
variable name is the pipeline's own convention, not a Nextflow built-in, and
the `NXF_` prefix is otherwise reserved for Nextflow's own settings (`NXF_VER`,
`NXF_HOME`, `NXF_OPTS`); keep it for compatibility with the case study or pick
a pipeline-specific prefix, but document it. The paper's anti-pattern
reminder: build the image from a Dockerfile with pinned sources, and never
fetch a script through a GitHub `/blob/` page URL, which returns HTML instead
of the raw file.

## 10. params.json versus nextflow.config (P4)

| Belongs in `params.json` (scientific, versioned with the analysis) | Belongs in `nextflow.config` (infrastructure, versioned with the site) |
|---|---|
| Input genomes and their identifiers | Executor, profiles, partition routing, account and QOS flags |
| Tool tuning (LASTZ scoring, seeding, chunk and overlap sizes) | Resource tiers (`withLabel`), `resourceLimits` or `check_max()` ceilings, `array` |
| Filtering and cleaning thresholds | Container image, conda settings, `NXF_CONTAINER_IMAGE` (pipeline-defined) handling |
| Output directory layout the science depends on | `errorStrategy`, `maxRetries`, executor polling settings |
| Nothing that names a queue, image, or CPU count | Debugging flags such as the P8 parity flag (declared in the schema, absent from `params.json`) |

```json
{
    "target_genome": "<<PATH_TO_TARGET>>",
    "query_genome":  "<<PATH_TO_QUERY>>",
    "lastz_y": 9400,
    "lastz_h": 2000,
    "chain_min_score": 1000,
    "seq1_chunk": 175000000
}
```

The keys above are illustrative; the rule is that every key is a scientific
parameter a tool invocation consumes (P9). `nextflow_schema.json` declares
every pipeline parameter, whether it comes from `params.json` or from
`params {}` in `nextflow.config`; with the nf-schema plugin and
`validateParameters()` in `main.nf`, `-params-file params.json` is validated
against it (Nextflow alone does not validate). Executor and process settings
are not covered by the schema.

## 11. Parity flag and comparator skeleton (P8)

```groovy
// nextflow.config: a debugging option, so it lives here and in the schema,
// not in params.json.
params {
    force_long_2bit = false   // force the rare 64-bit (V1) .2bit path on small inputs
}
```

```groovy
// modules/local/fa_to_two_bit/main.nf. Illustrative, and taken from the
// repository's change log rather than the paper: the paper says the writer
// produces V1 with `faToTwoBit -long`, the reader branches on the detected
// .2bit version, and `--force_long_2bit` forces the V1 path on small inputs.
// Whether your pipeline selects the rare path by size, by flag, or by
// detection is yours to decide; what matters is that the flag reaches it.
script:
def need_long = params.force_long_2bit || genome_fa.size() > 4.GB.toBytes()
def long_flag = need_long ? '-long' : ''
"""
faToTwoBit ${long_flag} ${genome_fa} ${meta.id}.2bit
"""
```

```json
"debug_options": {
    "title": "Debugging options",
    "type": "object",
    "properties": {
        "force_long_2bit": {
            "type": "boolean",
            "default": false,
            "hidden": true,
            "description": "Force the 64-bit .2bit (V1) path on small inputs for parity testing."
        }
    }
}
```

The paper's parity run:

```bash
nextflow run main.nf -params-file params.json --outdir results_v0
nextflow run main.nf -params-file params.json --outdir results_v1 --force_long_2bit
python3 standalone_scripts/compare_chains.py \
    results_v0/final/*.final.chain.gz \
    results_v1/final/*.final.chain.gz
```

Each glob must expand to exactly one file for the two-positional skeleton
below; name one file per side, or extend the skeleton to walk a directory.

Comparator skeleton. It matches on an overlap key rather than exact equality,
because the rare path may legitimately drift on shared upstream tool
internals, and it reports where the unmatched records sit (score tail,
partition boundaries) so a reviewer can judge whether the drift is benign.

```python
#!/usr/bin/env python3
"""Parity comparator skeleton (P8). Replace parse() for your record format;
the example reads UCSC chain headers:
chain <score> <tName> <tSize> <tStrand> <tStart> <tEnd> <qName> ..."""
import argparse, gzip, statistics
from collections import defaultdict

BUCKET = 100_000   # bp; candidates for a match share target, strand, and bucket

def parse(path):
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt") as fh:
        for line in fh:
            if line.startswith("chain "):
                f = line.split()
                yield {"score": int(f[1]), "t": f[2], "strand": f[4],
                       "start": int(f[5]), "end": int(f[6])}

def buckets(r):
    return range(r["start"] // BUCKET, r["end"] // BUCKET + 1)

def index(records):
    idx = defaultdict(list)
    for r in records:
        for b in buckets(r):
            idx[(r["t"], r["strand"], b)].append(r)
    return idx

def overlaps(a, b):
    return a["start"] < b["end"] and b["start"] < a["end"]

def near_boundary(r, bounds, window):
    return any(abs(r["start"] - p) <= window or abs(r["end"] - p) <= window
               for p in bounds.get(r["t"], ()))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("baseline"); ap.add_argument("candidate")
    ap.add_argument("--boundaries", help="file of '<tName> <pos>' partition boundaries")
    ap.add_argument("--window", type=int, default=10_000)
    a = ap.parse_args()
    base, cand = list(parse(a.baseline)), list(parse(a.candidate))
    cidx = index(cand)
    missing = [r for r in base if not any(overlaps(r, c) for b in buckets(r)
                                          for c in cidx.get((r["t"], r["strand"], b), ()))]
    print(f"baseline records            : {len(base)}")
    print(f"candidate records           : {len(cand)}")
    print(f"baseline without overlap    : {len(missing)} ({100 * len(missing) / max(1, len(base)):.3f}%)")
    if missing:
        print(f"median score, all baseline  : {statistics.median(r['score'] for r in base)}")
        print(f"median score, unmatched     : {statistics.median(r['score'] for r in missing)}")
    if a.boundaries:
        bounds = defaultdict(list)
        for line in open(a.boundaries):
            t, pos = line.split()[:2]
            bounds[t].append(int(pos))
        n = sum(near_boundary(r, bounds, a.window) for r in missing)
        print(f"unmatched within {a.window} bp of a partition boundary: {n}")

if __name__ == "__main__":
    main()
```

In the case study, this kind of comparison reported the V0 path reproducing
upstream chain for chain and the V1 path lacking an overlap match for about
0.11 percent of baseline chains, concentrated in the low-score tail and none
within 10 kb of a target-partition boundary. Report your own numbers the same
way, and say what the comparison does not establish (in the paper, the cause
of the drift).

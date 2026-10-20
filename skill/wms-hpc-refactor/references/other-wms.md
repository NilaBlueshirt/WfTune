# Mapping the practices beyond Nextflow

Scope statement first. The USRSE'26 paper (Mu, Dizon, Otero, Battelle)
measured one Nextflow pipeline on Slurm at one site. It did not measure
Snakemake, any other WMS, or any non-Slurm scheduler, and it says that other
sites and schedulers need separate measurement. Everything in this file is
therefore a mapping of the practices' reasoning onto other tools, offered as a
starting point. Where a mechanism is named, check it against the version of
the tool in front of you; where a number would be needed, there is none to
quote.

## Snakemake

Snakemake runs on Slurm through the official executor plugin
(`snakemake-executor-plugin-slurm`, selected with `--executor slurm` in
Snakemake 8 and later). The WfTune repository
(https://github.com/NilaBlueshirt/WfTune) states that it has Snakemake
adapters for its `native` and `jobarray` treatments built on that plugin, so a
site can run Snakemake under the same campaign protocol as Nextflow (frozen
inputs, role separation, evidence audit, semantic endpoint check). Snakemake
runs carry a workflow-level trace rather than Nextflow's per-task trace, so
compare completion time and RPC demand, not per-task metrics. Neither paper
reports Snakemake results.

| Practice | Snakemake counterpart (hedged) | Measured or stated in the paper? |
|---|---|---|
| P1 native tasks | Rules with wildcards and `expand()` give one job per output file; avoid a Python driver that enumerates work and calls `snakemake` once per stage, for the same reason as the joblist anti-pattern | Not measured for Snakemake; Nextflow only |
| P2 one tool per rule, stages | One rule per tool; `module:` and `use rule ... from` for reuse; target files, `--until`, and `--omit-from` give restart points without a custom state file | Not measured for Snakemake; the paper's Discussion lists modular processes as applying beyond comparative genomics |
| P3 legacy entry point | Keep the old CLI; expose the new workflow beside it | Not addressed for other WMS; this file's judgment that the reasoning transfers |
| P4 parameter split | Scientific values in `config.yaml` (`--configfile`); executor, partitions, and resources in a site profile (`--profile`, `--default-resources`, `--set-resources`) | Not measured for Snakemake; the paper's Discussion lists configuration separation as applying beyond comparative genomics |
| P5 dual directives | `conda:` and `container:` on each rule; `--software-deployment-method conda apptainer` selects at run time; `--containerize` emits a Dockerfile for the conda environments, from which one image is built; pin by digest | Not measured for Snakemake; Nextflow only |
| P6 site overlay | `--jobs N` caps in-flight jobs (the `queueSize` analogue); per-rule `resources:` with `attempt`-scaled lambdas for memory and `runtime`; `slurm_partition` chosen by runtime for walltime routing; the plugin's job-array option (`--slurm-array-jobs`, with `--slurm-array-limit`, present in recent versions of `snakemake-executor-plugin-slurm`; confirm for yours, and otherwise use `group:`) batches submissions; `--max-jobs-per-timespan` and `--max-status-checks-per-second` limit controller traffic; `group:` packs small jobs into one allocation, which is a different mechanism from arrays | Arrays measured for Nextflow only; none of the Snakemake knobs measured; the paper's Discussion says partition routing, Fairshare behavior, and controller settings depend on the scheduler and site |
| P7 strict failure handling | `--retries N` for per-job retries; outputs are required by default, so a missing declared output fails the job after `--latency-wait`; `--rerun-incomplete` after an interrupted run; `--keep-going` is the opposite of strict-by-default, so use it deliberately; an aggregating rule can assert expected versus actual counts; the watchdog pattern transfers if you hash the `N of M steps (x%) done` line of `.snakemake/log/<timestamp>.snakemake.log` instead of the Nextflow block; for the walltime case, the batch script is an `sbatch --wrap` shell that runs a per-job `snakemake` process, which runs the rule's `shell:` block, so a USR1 trap in that block sits two processes below the batch shell that `--signal=B:USR1@60` (via `slurm_extra`) targets, and what reaches it must be tested as in Step 10; the temporary-name plus `mv` pattern needs no signal | Watchdog evidence is Nextflow only; the USR1 trap is unverified even there (nextflow-snippets.md Section 7) |
| P8 parity flag | A config key (`--config force_rare_path=true`) that bypasses the threshold, plus the same comparator | Not addressed for other WMS; the paper's Discussion lists output comparison as applying beyond comparative genomics; the flag mechanism is this file's judgment |
| P9 parameter audit | Map every `config[...]` key to a rule that reads it; remove keys with no reader | Not addressed for other WMS; this file's judgment that the reasoning transfers |
| P10 silent-failure kit | `shell:` blocks run in bash strict mode in recent versions (confirm for yours); `run:` and `script:` blocks that call `subprocess` need `check=True`; Snakemake has no `optional: true`, but `touch()` flag outputs, `--keep-going`, and declaring fewer outputs than the tool should produce can hide a failure the same way | Not addressed for other WMS; this file's judgment that the reasoning transfers |

Two cautions specific to Snakemake. There is no `check_max()` helper; caps
belong inside the resource lambdas or the site profile, and an `attempt`-scaled
request needs a cap for the same reason as in Nextflow. And `--slurm-requeue`
lets Slurm requeue preempted or failed jobs outside Snakemake's own retry
accounting; decide which layer owns retries so a failure is not retried twice
and reported once.

## Nested schedulers and pilot-job patterns

HyperQueue, Flux, Parsl, and similar tools dispatch tasks inside allocations
Slurm has already granted. The USRSE'26 paper does not measure them. The
companion HPCSYSPROS'26 study (whose toolkit is released as Slurm-Stress-SC26
and packaged as WfTune) compared native
Slurm, job arrays, HyperQueue, and Flux for one Nextflow workload at one site
and recommends job arrays as the operational baseline there, reaching for a
nested scheduler only when the controller RPC budget, not walltime, is the
binding constraint, because aggregation trades away per-task visibility,
control, and accounting granularity. Treat that as one site's result and run
the decision procedure in SKILL.md Step 11 before adopting any of them.

## WMS-agnostic principles

These are the parts of the ten practices that do not depend on Nextflow
syntax. Each is stated with what backs it.

1. Make the engine's unit of work the scientific task, not a stage. Caching,
   retry, and resume only help at the granularity the engine can see (P1).
   Backed by the case study's design; the walltime effect of P1 alone was not
   isolated.
2. One tool per task, with per-task logs and exit status. Several tools in one
   task share one status and one log pair, which is where swallowed failures
   hide (P2, P10). Backed by the paper's observability argument in P10; Bug 1
   is its example of a wrapper-swallowed failure.
3. Keep the legacy entry point and use it as the characterization oracle (P3,
   discipline part 2). Backed by the case study's process.
4. Separate what the science owns from what the site owns, in different files
   (P4). Backed by the case study; it also enabled the P9 audit.
5. Pin the runtime by digest and keep a non-container fallback (P5).
6. Size per-task jobs to what they use, because a user whose Fairshare score
   has collapsed depends on backfill, and backfill starts only what fits (P6).
   Backed by the Fairshare trajectory in the paper; which scheduler path
   started each task was not identified.
7. Reduce submissions and polling per task where the WMS allows it, and verify
   the effect by counting submissions and timing the run; fewer submissions
   did not consistently mean shorter walltime in the case study (P6).
8. Fail the run when a task exhausts its retries, assert expected versus
   actual task counts after each many-task stage, supervise the main job from
   outside, and make sure a walltime kill leaves no complete-looking partial
   output and is recorded as a failure (P7). Backed by the
   case study's production recovery of a stalled 40,000-task run; thresholds
   are site choices.
9. Give every rare branch a flag and a comparator (P8). Backed by Bug 3 and
   the parity numbers in the case study.
10. Audit parameters at migration (P9) and never combine an unchecked return
    code with an optional output (P10). Backed by the three dead flags and by
    Bug 1.

And the discipline that wraps them, which is WMS-independent by construction:
record the change list before generating code, with references that predate
the refactor; compare outputs on a small realistic input before and after,
per unit and not only in total; and have a human read every generated change.
The paper reports that discipline as its process, not as a measured
productivity effect.

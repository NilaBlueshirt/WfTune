---
name: wms-hpc-refactor
description: >-
  Refactor, modernize, tune, harden, or review a workflow-management-system
  (WMS) scientific pipeline for shared Slurm HPC by applying ten practices and
  a three-part engineering discipline (pre-specification, characterization
  tests, human review of every change). Use it whenever the user asks to
  refactor, modernize, migrate, port, optimize, tune, harden, or review a
  Nextflow, nf-core, Snakemake, or other WMS pipeline for Slurm. Use it when,
  in the context of a workflow pipeline on a cluster, the conversation mentions
  job arrays, Fairshare, backfill, controller load, silent failures, optional
  outputs, unchecked subprocess.call, characterization or parity tests, nf-core
  DSL2 conversion, or a legacy Python-orchestrated pipeline. Use it when a
  pipeline fans out to thousands of per-task jobs, when a run finishes with
  missing data, when a main job stalls, or when someone wants to claim a
  speedup from a configuration change. Also use it to plan, review, or report
  such a refactor and to decide what to measure first.
---

# WMS pipeline refactoring for shared Slurm HPC

This skill turns the ten practices (P1 to P10) and the three-part engineering
discipline of the paper credited below into a working procedure for a coding
agent. The practices were distilled from refactoring `make_lastz_chains`, a
whole-genome pairwise alignment pipeline that fans out to about 40,000 LASTZ
tasks per mammalian genome pair, from a Python-orchestrated joblist design into
nf-core-style Nextflow DSL2 on Arizona State University's clusters (benchmarked
on Phoenix and Dev; Sol appears in the paper's scheduler-tuning comparison).
That pipeline is the worked example throughout; the instructions are generic.
Every measurement quoted in this skill comes from that one case study at that
one site, except the HPCSYSPROS'26 fragment in
`references/nextflow-snippets.md` Section 4, which is that companion study's
Phoenix default for a different workload. Treat all of them as illustrations,
never as guarantees for another pipeline or cluster.

Credit: N. T. Mu, W. Dizon, G. Otero, and T. Battelle, "Ten Practices for
Refactoring Scientific Pipelines to nf-core DSL2 on Shared Slurm HPC",
US Research Software Engineering Conference 2026 (USRSE'26),
https://doi.org/10.5281/zenodo.22921770. Public artifacts named in the paper: the refactored pipeline, container, and parity tooling at
https://github.com/NilaBlueshirt/make_lastz_chains (branch `nf-core-refactor`),
the benchmark scripts at https://github.com/NilaBlueshirt/WMS-on-HPC, and
upstream pull request #109. The measurement procedure in Step 11 follows the
companion HPCSYSPROS'26 study (artifact:
https://github.com/NilaBlueshirt/Slurm-Stress-SC26); the WfTune tool at
https://github.com/NilaBlueshirt/WfTune packages that procedure, and what this
skill says about `pip install wftune` and `wftune demo` comes from that
repository's documentation, not from either paper.

Terminology. Call the long-running WMS driver process the main job, and each
Slurm job it submits for one pipeline task a per-task job. Do not write "child
job": at the Slurm level these are independent submissions, and the label
implies a parent-child relationship the scheduler does not enforce.

## 1. When to use this skill, and what not to do

Use this skill when the request is to refactor, modernize, migrate, port,
optimize, tune, harden, or review a Nextflow, nf-core, Snakemake, or other WMS
pipeline that runs, or should run, on a shared Slurm cluster. Typical openings:
a legacy Python layer that writes joblists for a workflow engine, a pipeline
that submits one `sbatch` per task and drains the user's Fairshare score, a run
that finishes "successfully" with missing outputs, a main job that stalls after
a node failure, or a request to convert a pipeline to nf-core DSL2.

Keep these boundaries, because each one protects something the refactor is
supposed to preserve:

- Do not change scientific parameters (scoring, thresholds, chunk sizes,
  filters). The characterization tests in Step 2 compare refactored output with
  legacy output; a changed parameter invalidates that comparison and hides
  regressions behind "expected" differences. Treat any scientific change as a
  separate, pre-specified item with its own before-and-after comparison.
- Do not change the WMS. A Snakemake pipeline stays Snakemake and a Nextflow
  pipeline stays Nextflow unless the user explicitly asks for a migration;
  record such a request as pre-specified scope.
- Do not remove or alter a legacy entry point. Existing users and site
  procedures depend on it (P3). Add the new entry point beside it.
- Do not add `optional: true` to make a failure disappear. A missing required
  output is a signal; `optional: true` deletes the signal (P10). Reserve it for
  outputs that are genuinely optional in the science.
- Do not make a run pass by setting `errorStrategy` to `ignore` or `finish`,
  by `--keep-going`, by `|| true`, `set +e`, or redirecting stderr to
  `/dev/null` in a wrapper, or by widening an output glob. A red run is the
  signal Steps 2 and 10 exist to produce.
- Do not wrap shell calls without checking return codes. `subprocess.call`
  returns the exit code; ignoring it converts a tool failure into a wrapper
  success (P10). Use `subprocess.run(..., check=True)` or test the code.
- Do not claim a performance gain without a measurement. Walltime and
  submission counts come from logged timestamps and traces (Step 11), compared
  on the same input with the same scientific and executor settings. In the case
  study, job arrays cut submissions substantially but did not consistently
  shorten walltime, so "fewer submissions" is not evidence of "faster".
- Do not guess site limits. Partition walltimes, memory ceilings, array size
  limits, and scheduler parameters are site choices that can differ widely;
  even the paper's two clusters at one institution differ by two orders of
  magnitude on one backfill cap (`bf_max_job_assoc` 25 versus 2600). Ask for
  them, and list anything unconfirmed in the report.
- Do not run a production-scale input as a test on a shared cluster. Use the
  small realistic input from Step 2 under the `dev` profile
  (`references/nextflow-snippets.md` Section 4). Confirm with the user before
  the first submission and before any run that exceeds that profile, and run
  multi-task tests inside an allocation, not on a login node.
- Use a fresh work directory (`-w`) for every test. Never remove or resume into
  a work directory you did not create, and leave the legacy work and results
  directories untouched.
- Do not commit or push. Leave changes in the working tree with the change log
  so a human reviews every change (discipline part 3).

## 2. Gather inputs first

Collect three groups of facts before editing anything. P6 cannot be applied
without the site facts, the P7 thresholds depend on the workload facts, and the
P9 and P10 audits depend on the pipeline facts. Ask the user for whatever is
not in the repository or reachable with the commands below (all read-only; a
denied command goes into report item 4), and record what remains unknown so it
appears in the report's list of site values to confirm.

Site facts:

- Scheduler and version (`sinfo -V`), WMS version (Nextflow `process.array`
  needs 24.04.0 or later; if the legacy is DSL1, run it with
  `NXF_VER=22.10.x`, the last series with DSL1, and the refactor with
  `NXF_VER=24.04.0` or later, recording both), the container runtime available
  (Apptainer, Singularity, Docker), and whether the registry is reachable from
  compute nodes.
- Partitions with their walltime, memory, and CPU limits, and any required
  account or QOS flags (`scontrol show partition`, `sacctmgr show qos`).
- `SchedulerParameters` that govern bulk submission
  (`scontrol show config | grep -E 'SchedulerParameters|MaxArraySize|MaxJobCount'`):
  `bf_max_job_assoc`, `bf_max_job_user`, `bf_max_job_start`, `bf_max_job_test`,
  `max_rpc_cnt`, `bf_yield_rpc_cnt`, plus `MaxArraySize` and `MaxJobCount`. The
  array batch size has to fit under `MaxArraySize`; the other caps decide how
  much fan-out the controller absorbs.
- Per-user and per-QOS submit limits, which bound `queueSize`:
  `sacctmgr show assoc where user=$USER format=Account,Partition,QOS,MaxJobs,MaxSubmit`
  and `sacctmgr show qos format=Name,MaxJobsPU,MaxSubmitPU,MaxWall`.
- Fairshare policy: whether it is enabled, how usage decays, and whether the
  user's score is already low. A low score reduces the priority contribution
  from Fairshare and makes backfill opportunities more important, which is why
  per-task jobs are sized to fit backfill windows (the paper does not identify
  which scheduler path started each task).
- Where the work directory lives (shared-filesystem latency affects
  `exitReadTimeout`), and whether a login-node process or a small separate
  Slurm job may host the watchdog.

Workload facts:

- Task count per stage, and which stage dominates (the many-task stage).
- Task runtime distribution (median, spread, tail) and per-task CPU, memory,
  and walltime actually used, from a previous run's Nextflow `report.html` or
  `trace.txt`, or, for a legacy without a trace, from `sacct` on its per-task
  jobs (command in Step 5). Running `seff` on the main job alone describes
  nothing about the separate per-task allocations.
- DAG depth, input sizes, and any format or size threshold that switches a code
  path (the case study has a V1 `.2bit` path required for genomes over 4 GB,
  taken by detected version).
- The expected cardinality of the many-task stage (for the integrity check),
  and a small realistic input that completes in minutes (Step 2 says how to
  choose one).

Pipeline facts:

- Orchestration pattern: does a script enumerate work items into a joblist and
  call the engine once per stage, or does the engine see each task?
- Wrappers that call `subprocess.call`, `os.system`, or shell pipelines, and
  whether their return codes are checked.
- Configuration files and what each one mixes (scientific parameters next to
  queue names is the P4 smell).
- Every `optional: true` output, every CLI flag, and every restart mechanism
  (step-state JSON files, `--continue_from_step` style flags).
- Existing `errorStrategy`, `maxRetries`, `maxErrors`, `conda`, `container`,
  tests, reference outputs, and open upstream issues (these feed Step 1).

## 3. The workflow, in order

Scope the run first. Review: Section 2, Steps 1 to 3, and the Section 5
report, with no code changes. Tune or harden an existing WMS pipeline: Steps 1
to 3, 5, 6, 9, 10, and 11, marking P1 to P5 done or not applicable with the
Section 4 check as evidence. Refactor or migrate: all steps. If the pipeline
is Snakemake, read `references/other-wms.md` now and substitute its
counterparts for every Nextflow mechanism in Steps 4 to 9. If the scheduler is
not Slurm, stop: the P6 and P7 overlays here are Slurm-specific and need a
translation the references do not provide.

The order matters. Verification scaffolding (Steps 1 to 3) comes first because
every later step is checked against it. Architecture (Step 4) precedes the site
overlay (Step 5) because sizing and arrays attach to processes that exist only
after decomposition. Failure handling (Step 6) precedes parity, parameter
removal, and silent-failure fixes (Steps 7 to 9) so that the parity runs
themselves fail loudly.

Step 1. Pre-specify from observation (discipline part 1). Write the change list
before changing any code, from observed behavior of the legacy pipeline on
real data: issue numbers, log excerpts, operational notes, prior runs. Give
each item a durable reference that predates the refactor. In the case study the
record was a published operational paper, public issues filed upstream, and a
deployment-recipe repository. If no such record exists, create one now: a
dated `docs/refactor-prespec.md`, committed by the user before the first code
change, each item citing a file and line, a log excerpt, or a command and its
output. Never cite an issue, paper, or note you have not read; mark anything
unverifiable as such. The Step 2 baseline run may come before the Step 1
write-up to supply observations, provided the change list is recorded before
any code is changed. Each later change cites one of these items in the change
log. This keeps scope honest (the large-genome item kept both the writer change
and the reader change in scope, plus preservation of the existing path) and
lets a reviewer check that a change addressed the intended problem rather than
a problem invented during implementation.

Step 2. Characterize (discipline part 2). Run the legacy pipeline on a small
but realistic input and keep its outputs as the reference:

1. Input. Take the smallest subset that exercises every stage and at least one
   of each unit class the many-task stage branches on (one large chromosome,
   several small scaffolds, both strands), with task cardinality above the
   development `array` value so arrays are exercised, completing in minutes in
   an interactive allocation. Run the legacy end to end on it and list which
   code paths it does not reach; those need Step 7 flags.
2. Determinism. Run the legacy twice on the same input. Any output that differs
   between the two runs is not byte-comparable; classify it as order-varying
   or as legitimate drift.
3. Compare rule per output. `cmp` on decompressed streams for deterministic
   files (`cmp` on `.gz` files always differs, because gzip headers carry
   mtimes). For order-varying files,
   `diff <(gzip -dc a.gz | normalize | LC_ALL=C sort) <(gzip -dc b.gz | normalize | LC_ALL=C sort)`,
   where `normalize` is a documented `sed` that strips timestamps, paths,
   hostnames, and version strings. For drift, a domain comparator that matches
   on a bucket key and reports matched, missing, and score distribution
   (`references/nextflow-snippets.md` Section 11).
4. Per unit. Loop over the unit list (for example `cut -f1 target.sizes`) and
   compare counts and content per unit, reporting a table, not only totals.
   Per-target comparison is what exposed missing chains for small scaffolds in
   the case study, where a latent filename-length bug had silently cost about
   23 percent of alignment coverage in one amphibian sample.
5. Reference storage. Keep the reference in a read-only directory outside
   `work/`, with `sha256sum` of every file, the exact command, `NXF_VER`, each
   tool's `--version` from the legacy environment (Step 4 pins to these), and
   the legacy commit or checksum.

A run that exits zero is not the same as a scientifically complete result.

Step 3. Audit. Produce three tables from the pipeline facts: every CLI
parameter mapped to the tool invocation that consumes it (or "no consumer");
every shell call with whether its return code is checked; every
`optional: true` output with whether the science makes it optional. Mark a
parameter "no consumer" only when both a direct search for its name and a
search for dynamic access (`vars(args)`, `getattr(args, name)`, `**kwargs`,
template or f-string expansion of all parameters, Snakemake `config.get(...)`,
parameters written to a file a tool then reads) come back empty. These tables
drive Steps 8 and 9, they are the first place a silent-failure kit becomes
visible, and they are attached to the report.

Step 4. Refactor the architecture (P1 to P5). If `trace.txt` already shows one
row per work item and no joblist file is written, P1 is not applicable; if
every process already wraps one tool, P2 is not applicable. Otherwise, replace
joblist generation with channel operators (`combine`, `flatMap`) so the engine
sees individual tasks and can cache, retry, and resume them (P1). Wrap one
tool per process; declare `label`, `conda`, `container`, `publishDir`, and a
`versions.yml` output; group processes into subworkflows by stage; expose
named `-entry` points for long-running stages in place of custom step-state
files (P2; the case study went from seven steps to 14 modules in four
subworkflows with two restart entries). For each process, diff the legacy
joblist line for one task against the generated `.command.sh` after
normalizing paths; every difference goes into the change log with its reason.
Keep the legacy CLI unchanged beside the new `nextflow run main.nf` entry point
(P3). Split `params.json` (scientific) from `nextflow.config` (infrastructure)
(P4). Give every module both a `conda` and a `container` directive, provide an
environment-variable override for the image (the case study's
`NXF_CONTAINER_IMAGE` is pipeline-defined, not a Nextflow built-in, and the
`NXF_` prefix is otherwise Nextflow's own), and pin the image by digest (P5).
Obtain the digest only from a registry or image query (commands in
`references/nextflow-snippets.md` Section 9); if none is reachable, leave
`<<DIGEST>>` in place and list it under report item 4. Pin `environment.yml`
and the Dockerfile to the tool versions the legacy run used (Step 2, item 5);
any version change is a separate pre-specified item with its own comparison.
Do not build images on a login node or without the user's go-ahead. Use a
global `process.container` only when the pipeline ships one image holding
every tool; with per-tool images, keep the module directives and override per
module (Section 9 of the same file). Rerun the Step 2 comparison after each of
these; architecture changes are where regressions enter.

Step 5. Overlay the site (P6). Six changes, in this order, all driven by the
site and workload facts. First get numbers: from
`sacct -j <legacy job ids> --format=JobID,JobName,MaxRSS,Elapsed,ReqMem,Timelimit,NCPUS,TotalCPU`
on a prior legacy run, or from a trace-enabled run of the Step 4 result on the
small input with generous tiers; note whether per-task work is fixed by a
chunk parameter (then small-input tasks are representative) or scales with
input size (then they are not). Then: (1) size each tier's CPU, memory, and
walltime to what tasks use, memory at peak RSS plus headroom and time at the
tail, never below observed use, so per-task jobs fit backfill windows; (2) cap
dynamically scaled requests with `resourceLimits` (Nextflow 24.04 or later;
the case study used nf-core's `check_max()` helper) so retries are not
rejected at submission; (3) route each `withLabel` tier to the partition whose
walltime class fits; (4) set `process.array` on the many-task processes (the
case study used 500 on three processes, under the site's `MaxArraySize`); (5)
set `pollInterval`, `queueStatInterval`, `exitReadTimeout`, `queueSize`,
`submitRateLimit`, and `killBatchSize` to limit controller traffic and tolerate
delayed exit files; (6) prepare shared inputs once, passed as a `path` input,
instead of once per task, and rerun the Step 2 comparison after it because it
changes the DAG. Enable `report`, `timeline`, and `trace`. Take the fragments
from `references/nextflow-snippets.md` and set every site-specific value from
the facts gathered in Section 2.

Step 6. Add failure handling (P7). Four layers. First, strict-by-default
`errorStrategy = 'retry'` with a single `maxRetries`, so a task that exhausts
its retries fails the run (`maxErrors` bounds failures across a process and is
unlimited by default; a finite value such as 25 on a many-task process makes a
systematic failure abort early instead of retrying every task). Second, a
post-stage integrity check that compares the materialized expected pair count
with the count of completion records and raises an error on mismatch. Third,
an out-of-band watchdog that content-hashes the latest "tasks to be
completed" block of `.nextflow.log`, cancels the main job after
`STALL_THRESHOLD` seconds without change (default 30 minutes; keep it above
`executor.dumpInterval`), resubmits with `-resume` through a script that reuses
the main job's unique `--job-name`, and stops after `MAX_RESTARTS` (default 5);
it runs outside the main job because an `scancel` issued from inside would
kill the watchdog along with the main job, and it checks the job's `WorkDir`
before cancelling. Fourth, partial-output protection at walltime: write every
output under a temporary name and `mv` it into place last, so a kill cannot
leave a complete-looking file. The paper adds
`clusterOptions = '--signal=B:USR1@60'` plus a USR1 trap in the task script;
Nextflow's stock `.command.run` sets `trap '' USR1`, so under it that trap
never fires, and the wrapper's own TERM handling plus the temporary-name
pattern do the work. Read `references/nextflow-snippets.md` Section 7 before
installing any trap, and record in the checklist which mechanism the Step 10
test showed.

Step 7. Add parity flags for divergent paths (P8). For every branch taken only
on rare inputs (size thresholds, format versions), add a CLI flag that forces
the rare branch on the small input, mark it as a debugging option recognized by
the schema but absent from `params.json`, and pair it with a comparator that
quantifies divergence between the two paths' final outputs. In the case study
the flag caught an incorrect command builder on a small genome before any
production run, and the comparator later showed the common path reproducing
upstream chain for chain while the rare path lacked an overlap match for about
0.11 percent of baseline chains, concentrated in the low-score tail.

Step 8. Remove dead parameters (P9). Using the Step 3 table, propose every
flag with no consumer for removal from the new interface, have the user
confirm each one, and say so in the change log (the case study found three).
Declare each removed key in `nextflow_schema.json` as deprecated, with a
description naming the pre-specified item, so an old params file produces a
named warning rather than a bare validation failure (confirm how your schema
validator handles `deprecated`). Leave the legacy CLI untouched.

Step 9. Close the silent-failure kit (P10). Using the Step 3 tables, make every
wrapper propagate non-zero return codes. For each `optional: true` row, ask the
user to confirm what the science requires before changing it; where the Step 2
input shows a legitimately empty result, prefer an explicitly written empty
output over an optional one, so the task still proves it ran. Prefer one
process per tool so each task has its own `.command.sh`, `.command.out`,
`.command.err`, and `.exitcode`; several tools inside one task share one status
and one log pair, which is where swallowed failures hide.

Step 10. Verify, under the `dev` profile (`maxRetries = 1`, small `queueSize`
and `array`). Rerun the Step 2 comparison under each runtime profile; run the
parity flag and comparator; confirm the integrity count matches; inject a
failure through a test config, for example
`withName: LASTZ { beforeScript = { task.index == 3 ? 'exit 1' : 'true' } }`,
and confirm the run aborts instead of completing with missing data; run one
task with a deliberately short `time` and record which mechanism produced the
failure (if `.exitcode` is non-zero and no partial file remains, layer 4 is
done; if the USR1 trap never fired, record layer 4 as "partial: temporary
name plus mv only" and do not call it graceful termination in the report);
simulate a stall on a development run (for example by pausing the main job's
Nextflow process) with `STALL_THRESHOLD=120 CHECK_INTERVAL=30` and confirm the
watchdog logs it and performs the cancel-and-resume once. Record each result
in the checklist.

Step 11. Measure. Report walltime from logged timestamps (pipeline invocation
to completion, or to a declared milestone such as the end of the many-task
stage), the count of distinct `sbatch` submissions (array-base job IDs from
the `native_id` column of `trace.txt`:
`awk -F'\t' 'NR==1{for(i=1;i<=NF;i++)if($i=="native_id")c=i;next}{sub(/_.*/,"",$c);print $c}' trace.txt | sort -u | wc -l`),
and per-task resource use from the Nextflow trace. Compare like with like:
same input, same scientific parameters, same executor settings, and state what
else differed (contention, hardware). When the user asks which deployment
strategy a site should adopt (native per-task jobs, job arrays, or a nested
scheduler such as HyperQueue or Flux), the companion HPCSYSPROS'26 study's
procedure applies: fix a representative input and a correctness-gated
milestone, set the controller RPC budget before measuring, reject strategies
on constraints (budget, grantable capacity, accounting granularity, site
policy) rather than on speed, pick the fastest survivor, and re-measure when
the workload class changes. Its toolkit (Slurm-Stress-SC26, packaged as
WfTune) records completion time alongside the RPC demand attributable to the
benchmark user. Run such a campaign, or install any package for it, only on
the user's explicit request; the tool's documentation states that
`wftune demo` output is fabricated and never to be reported. Label every
result with the site and workload it came from.

## 4. The ten practices at a glance

| # | Practice | Smell that triggers it | Check that proves it |
|---|---|---|---|
| P1 | Decompose Python orchestration into native channels | A script writes a joblist file and calls the engine once per stage | Each work item is its own row in `trace.txt`; `-resume` skips completed items individually |
| P2 | One process per tool; subworkflows by stage | One script runs several tools; restart relies on a custom step-state file or `--continue_from_step` | Every task directory has its own `.command.sh`, `.command.err`, `.exitcode`; each long stage restarts via `-entry` |
| P3 | Backward-compatible legacy entry point | The migration rewrites or deletes the old CLI | The old command runs unchanged and reproduces its reference output |
| P4 | Separate scientific from infrastructure parameters | Queue names and container tags sit next to scoring thresholds in one file | `params.json` holds no partition, image, or label keys; `nextflow.config` holds no scientific values |
| P5 | Dual conda and container directives | Tools fetched by `wget` at build time; `/blob/` URLs; no image digest | Every module declares `conda` and `container`; the image is pinned by digest; Step 2 passes under both profiles |
| P6 | HPC-aware overlay on nf-core defaults | Default tiers unchanged; one `sbatch` per task; retries rejected for exceeding partition limits | `report.html` request versus use per tier; distinct `sbatch` count falls; no submission rejections on retry |
| P7 | Strict error handling, integrity check, watchdog, partial-output protection | `errorStrategy = 'ignore'` on a required stage, or a retry closure that returns `ignore` or `finish` for ordinary exit codes; a run completes with fewer outputs than tasks; a stalled main job after node failure | An injected failure aborts the run; expected count equals completion records; the watchdog restarts a simulated stall; a short-walltime task leaves no partial file |
| P8 | Parity flag for divergent code paths | An `if size > threshold` branch exercised only on huge inputs | The flag runs the rare path on the small input; the comparator reports matched, missing, and score distribution |
| P9 | Audit parameters during migration | Flags accepted but consumed by no tool invocation | Every parameter maps to an invocation or is removed and listed |
| P10 | Refuse the silent-failure construction kit | `subprocess.call` without a return-code check; `optional: true` on required outputs | A forced tool failure fails the task; `optional: true` survives only where the science allows a missing output |

## 5. Report format

End with one report in this shape, so a reviewer can check it against the
pre-specification:

1. Refactor plan: the pre-specified change list with its durable references,
   the small reference input, the comparison rule per output, and the site and
   workload facts used.
2. Checklist table: one row per practice (P1 to P10) with status (done,
   partial, not applicable, blocked), the files or modules touched, and the
   check from Section 4 that was run, with its result.
3. Change log: one entry per change, each naming the pre-specified item it
   addresses, the files changed, and the before-and-after comparison result.
   A change that addresses no pre-specified item is either new scope (record
   it as such and get it approved) or a mistake.
4. Site values still needing confirmation: every placeholder left in the
   configuration (partition names, limits, array size, executor rates, account
   or QOS flags, image digest) and every scheduler parameter that was assumed
   rather than read from the site.
5. Measurements, if any, with the input, site, configuration, and what
   differed between compared runs; otherwise a plain statement that no
   performance claim is made.
6. Audit and mapping tables: the three Step 3 tables, and an output mapping
   that pairs each legacy output path with the refactored output path and the
   comparison rule applied.

## 6. Reference files

- `references/practices.md`: the ten practices (the paper's anti-pattern and
  recommendation for each, its Mechanism for P7 and P8 and Evidence for P6 to
  P8, plus this skill's labelled Mechanism and How-to-verify additions), the
  three-part discipline with its three bugs, and the case study's
  measurements. Read the discipline section before Step 1 and P1 to P10 before
  Step 4, and whenever you need a practice's reasoning or exact numbers.
- `references/nextflow-snippets.md`: copyable Nextflow configuration and DSL2
  fragments for P5 to P8, with every site-specific value marked as a
  placeholder. Read it at Steps 4 to 7 when writing configuration.
- `references/other-wms.md`: mapping the practices to Snakemake and to
  WMS-agnostic principles, stating what the paper did and did not measure.
  Read it when the pipeline is not Nextflow (the Section 3 preamble sends you
  there before Step 4).

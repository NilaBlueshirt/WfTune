# The ten practices in full

Restated from N. T. Mu, W. Dizon, G. Otero, and T. Battelle, "Ten Practices
for Refactoring Scientific Pipelines to nf-core DSL2 on Shared Slurm HPC",
USRSE'26: Section 3 (practices), Section 4 (engineering discipline), and
Section 5 (performance evidence). Artifacts named in the paper: the pipeline at
https://github.com/NilaBlueshirt/make_lastz_chains (branch `nf-core-refactor`),
the benchmark scripts at https://github.com/NilaBlueshirt/WMS-on-HPC, and
upstream pull request #109. The companion HPCSYSPROS'26 study's artifact is
https://github.com/NilaBlueshirt/Slurm-Stress-SC26; the WfTune tool
(https://github.com/NilaBlueshirt/WfTune) packages it and is named in neither
paper.

The paper states an anti-pattern and recommendation for every practice, a
Mechanism paragraph only for P7 and P8, and Evidence only for P6 to P8. The
remaining Mechanism paragraphs and every How-to-verify paragraph below are
this skill's additions, consistent with the paper but not quoted from it.

Every "Evidence from the case study" entry describes one pipeline
(`make_lastz_chains`) at one site (Arizona State University; measurements on
the Phoenix and Dev clusters, with Sol as the paper's tuning comparison). The
paper bounds its findings to that workflow and site. Quote the numbers as that
study's results, never as expected outcomes elsewhere.

## The case study in one paragraph

`make_lastz_chains` produces sorted alignment chains (gap-aware stitched
alignments) between two genomes with LASTZ and the UCSC Kent toolkit. A typical
mammalian alignment fans out to about 40,000 LASTZ tasks; assemblies with many
small scaffolds can exceed 50,000 tasks per run. The original pipeline used
Nextflow as a parallel job runner driven by a Python layer: `make_chains.py`
generated joblist files that a Nextflow wrapper executed. Earlier operational
work on the Phoenix cluster documented rapid Fairshare-score consumption, no
per-task-job retry by default, and per-task exit codes not consistently
propagated. Those observations, a year of upstream issue filings, and a local
deployment recipe produced a change list large enough to motivate a full
refactor rather than continued patching. The authors note that the
anti-patterns are not specific to this pipeline; they observe them in many
bioinformatics tools that predate nf-core.

Terminology: the main job is the long-running Nextflow driver; a per-task job
is each Slurm job it submits for one pipeline task. The paper avoids "child
job" because Slurm does not track these submissions as dependents.

P1 to P5 and P9 cover baseline modernization and nf-core-style conventions.
P6 to P8 and P10 carry the shared-HPC execution and verification lessons.

## P1: Decompose Python orchestration into native channels

Anti-pattern. A Python wrapper enumerates work items, writes them to a shell
joblist, and invokes a workflow engine to run the joblist. The engine sees one
opaque per-stage invocation and cannot apply per-task caching, retry, or resume
semantics.

Recommendation. Replace the joblist-file pattern with native Nextflow channel
operators (`combine`, `flatMap`). Per-task caching, retry, and resume then
operate on individual tasks rather than on opaque joblist invocations.

Mechanism. The engine's unit of work becomes the scientific task. Cache keys,
retry counters, and resume state attach to each work item instead of to a
stage-level invocation, and the Python wrapper leaves the parallel hot path.

How to verify. `trace.txt` shows one row per work item for the stage. Killing
a run and restarting with `-resume` reuses cached items and reruns only the
incomplete ones. No joblist file is written in the work directory.

Evidence from the case study. The refactored LASTZ subworkflow uses `combine`
to materialize the N x K target-query partition pairs natively, eliminating the
joblist file and the Python wrapper from the parallel hot path.

## P2: One process per tool; group into subworkflows by stage

Anti-pattern. A monolithic pipeline with no clean restart points relies on a
custom JSON step-state manager (for example `--continue_from_step`) that
becomes a source of confusion when users move intermediate outputs between
directories.

Recommendation. A module here is a reusable Nextflow DSL2 component containing
a process that wraps one tool (distinct from an HPC environment module). Each
module declares `label`, `conda`, `container`, `publishDir`, and a
`versions.yml` output. Modules group into subworkflows by pipeline stage. The
result is independently testable units, version-tracked provenance, and clean
restart points via Nextflow's `-entry` flag.

Mechanism. Restart points become first-class workflow entries that take a
published intermediate as input, so no separate state file has to agree with
the filesystem. One tool per process also restores layered observability
(see P10): each task carries its own `.command.sh`, `.command.out`,
`.command.err`, and `.exitcode`, and `trace.txt`, `report.html`, and
`timeline.html` give the cross-task view.

How to verify. Each module has the five declarations. Each named entry is
documented with the published file it consumes and runs from that file alone.
A failure can be traced to one task working directory.

Evidence from the case study. The refactor decomposes the original seven steps
into 14 modules grouped under four subworkflows. Two named restart entries
cover the long-running stages: `FROM_FILL_CHAINS` resumes from a published
`*.all.chain.gz` (via `--merged_chain`) and `FROM_CLEAN_CHAINS` resumes from a
`*.filled.chain.gz` (via `--filled_chain`). Together they replace the legacy
`--continue_from_step` flag and its custom JSON step-state manager.

## P3: Backward-compatible legacy entry point

Anti-pattern. A refactor that replaces the original CLI forces every existing
user to migrate on the refactor's schedule and stalls adoption at sites where
the legacy pipeline is embedded in established procedures.

Recommendation. Preserve the original CLI unchanged and add the new pipeline
alongside it. Existing users see no change; new users opt in.

Mechanism. Adoption is decoupled from the release. The untouched legacy path
also remains available as the oracle for characterization tests for as long as
it exists.

How to verify. The legacy entry script is byte-identical to the legacy as found
at the start of the refactor (record its commit or checksum). The legacy
command runs on the reference input and reproduces the reference output.

Evidence from the case study. The refactor preserves `make_chains.py`
verbatim; `nextflow run main.nf` is the new entry point.

## P4: Separate scientific from infrastructure parameters

Anti-pattern. A single configuration file holds both scientific tuning
parameters (for example LASTZ scoring) and infrastructure parameters (for
example Slurm queue names). Users editing one routinely break the other, and
reproducing a run requires forking the configuration.

Recommendation. `params.json` holds versionable scientific parameters (LASTZ
tuning, chain-cleaner thresholds); `nextflow.config` holds infrastructure
(labels, profiles, container images).

Mechanism. Scientific parameters can be versioned separately from site
configuration, and it becomes visible which parameters reach which layer. In
the case study this visibility is what enabled the parameter audit (P9).

How to verify. `params.json` contains no partition, queue, image, CPU, memory,
or label keys. `nextflow.config` contains no scientific values. The same
`params.json` on two sites yields identical scientific settings.

Evidence from the case study. As stated above; the separation enabled the P9
audit.

## P5: Containerize with dual conda and container directives

Anti-pattern. Tool installation by per-binary `wget` calls against
version-mutable upstream sources is not reproducible. Revisiting a run a year
later finds different tool versions, and certain URL formats (for example
GitHub `/blob/` pages) return an HTML wrapper rather than the raw source,
producing build outputs that diverge from intent without a clear failure
signal.

Recommendation. Each module declares both a `conda` environment and a
`container` image; the active runtime profile (`-profile conda` or
`-profile apptainer`) selects which is used. Provide an environment-variable
override (`NXF_CONTAINER_IMAGE`) so sites without registry access can swap in
a local build. `NXF_CONTAINER_IMAGE` is this pipeline's own variable, read in
`nextflow.config` with `System.getenv()`; Nextflow has no built-in by that
name, and the `NXF_` prefix is otherwise reserved for Nextflow's own settings,
so consider a pipeline-specific prefix in a new refactor. For reproducible
runs, pin the image by digest rather than relying on a mutable tag.

Mechanism. The runtime becomes an artifact with an identity (a digest) rather
than a procedure (a download script). The dual directive keeps a conda path for
sites without a container runtime, and the override keeps the container path
for sites without registry access. The pattern is portable across Docker,
Apptainer, and Singularity.

How to verify. The build fetches nothing by unpinned URL, and raw URLs replace
`/blob/` pages. The image digest is recorded with each run. Step 2
characterization passes under both profiles.

Evidence from the case study. The refactor ships a single image
(`nilablueshirt/make_lastz_chains:latest-amd64`) built from a Dockerfile in
the repository, holding the UCSC Kent toolkit, LASTZ, and pinned auxiliary
scripts; `NXF_CONTAINER_IMAGE` overrides the default. That is the shipped,
mutable tag: the paper's own digest recommendation goes beyond what the
released pipeline did, so do not read the tag as licence to ship one.

## P6: HPC-aware overlay on nf-core defaults

Anti-pattern. nf-core's standard `withLabel` resource tiers (`process_low`,
`process_medium`, `process_high`) need adaptation to local partitions and
resource limits. Unadapted settings can request more resources than tasks
need, exceed partition limits on retries, or generate excessive submission
traffic.

Recommendation. Apply six configuration and workflow changes.

1. Backfill-fit per-task-job sizing. Resource consumption during a large run
   can rapidly reduce the user's Fairshare score, making backfill
   opportunities more important. Requesting only the CPU, memory, and walltime
   each process needs helps its tasks fit available scheduling windows. Use a
   representative test and Nextflow's `report.html` to examine per-task
   resource use and duration; `seff` on the main job alone does not describe
   the separate task allocations. Faster task scheduling can also reduce the
   time the main job has to remain active.
2. Slurm job arrays via `process.array`. For many-task steps, batch tasks into
   fewer `sbatch` submissions while retaining separate task execution. The
   directive has been available since Nextflow v24.04.0.
3. Walltime-based partition routing. Bind each `withLabel` tier to the
   partition whose walltime class fits. Short-running tasks (2 hours or less)
   go to a higher-throughput partition; longer tasks go to general-purpose
   partitions. This eliminates a class of user error.
4. Resource caps via `check_max()`. Wrap dynamically scaled resource requests
   (`memory = { 4.GB * task.attempt }`) with a helper that caps each scaled
   request against partition hard limits, so retried jobs are not rejected at
   submission for asking too much.
5. Limit controller traffic and handle delayed task status. High-volume runs
   can encounter controller communication timeouts and missing task exit
   files. The case study used `pollInterval = '30 sec'` and
   `queueStatInterval = '2 min'` to reduce polling frequency, `queueSize` to
   limit in-flight tasks, `killBatchSize` to batch cancellations, and
   `exitReadTimeout = '15 min'` to allow time for an exit file to become
   visible. These settings balance responsiveness against controller traffic
   and should be tuned for the site. Smaller `queueSize` and `array` values
   suit short development tests.
6. Prepare shared input once. When many tasks read the same genome, extract
   chromosome sequence files once (FASTA) and pass their directory as a
   Nextflow `path` input; on a shared filesystem tasks then use symlinks. A
   per-task cache remains as a fallback for entry points that bypass this
   preparation step.

Enable Nextflow's report, timeline, and trace outputs to inspect per-task
resource use, execution time, and waiting time. They help assess the
configuration, although they do not by themselves identify which Slurm
scheduling path started a job.

Mechanism. The chain is Fairshare to backfill: a large run consumes the user's
Fairshare contribution to priority, backfill opportunities become more
important, and backfill starts a job only when it fits a window without
delaying higher-priority jobs. The paper does not identify which path started
each task. Smaller, accurately sized per-task jobs fit more windows;
arrays and polling settings reduce the controller work that each task costs;
routing and caps stop submissions from being rejected; shared input
preparation removes repeated work from every task.

How to verify. Compare requested versus used CPU, memory, and time per tier in
`report.html`. Count distinct `sbatch` submissions (unique array-base job IDs
in `.nextflow.log` and `trace.txt`) before and after. Confirm no retry is
rejected at submission. Confirm the array size is below `MaxArraySize` and the
in-flight cap respects the site's submit limits.

Evidence from the case study. The refactor sets `array = 500` on `LASTZ`,
`AXT_CHAIN`, and `REPEAT_FILLER`. Short tasks route to a higher-throughput
partition and longer tasks to the general-purpose partition. The
`EXTRACT_CHROMS` module implements the shared-input preparation for the V1
`.2bit` reader path. The paper's Fairshare figure shows the user's score
dropping to near zero early in the LASTZ workload and staying there for the
rest of the run. Section 5 of the paper (summarized below) measures the effects
of the job-array overlay on walltime and scheduler activity.

## P7: Strict-by-default error handling and post-stage integrity checks

Anti-pattern. Retry settings cannot detect a failure that a wrapper reports as
success; in particular, the unchecked return codes and optional outputs of P10
can hide missing data. Separately, `maxErrors` limits failures across a
process, while `maxRetries` limits retries of an individual task; unlimited
`maxErrors` does not make exhausted task retries harmless.

Recommendation. Four layers of defense.

1. Strict-by-default `errorStrategy`: `errorStrategy = 'retry'` with
   `maxRetries = 8`. The retry limit is specified once; a task that continues
   to fail beyond it fails the run.
2. Post-stage integrity-check assertion. At the end of any many-task stage,
   materialize the expected (target x query) pair list and compare its length
   against the count of task completion records; report a mismatch as an
   error. This complements scientific output comparison, since a wrapper that
   falsely reports success can still produce a completion record. (Listing in
   `nextflow-snippets.md`, from `subworkflows/local/lastz_alignment/main.nf`.)
3. Out-of-band watchdog. The residual failure mode is a stalled main job that
   has lost sight of a task that disappeared from Slurm without writing
   `.exitcode`, for example after `NODE_FAIL` or an RPC timeout. If the failure
   never reaches Nextflow, `errorStrategy = 'retry'` cannot fire and the run
   stays stalled. A small external watchdog (on the login node in `tmux` or
   `screen`, or as a separate small Slurm job) content-hashes the most recent
   "tasks to be completed: N" block in `.nextflow.log`. If the hash is
   unchanged for `STALL_THRESHOLD` seconds (default 30 minutes) it cancels the
   main job with `scancel` and resubmits it with `-resume`. A `MAX_RESTARTS`
   cap (default 5) prevents infinite resubmit loops during persistent cluster
   failures. The watchdog never runs as part of the main job, since its own
   `scancel` would then kill it along with the main job.
4. Graceful per-task-job termination on the walltime signal. A task that
   reaches its walltime during a write can leave partial files. Add
   `clusterOptions = '--signal=B:USR1@60'` to many-task processes and trap the
   signal in the task script to remove partial outputs and exit non-zero
   before Slurm's hard kill. The non-zero exit makes the failure visible to
   the retry policy. (Nextflow's stock `.command.run` sets `trap '' USR1`, so
   this trap does not fire under it, and the released pipeline's change log
   records no trap; `nextflow-snippets.md` Section 7 says what does work.)

Mechanism (the paper's sentence: the layers address different failure modes
and complement the return-code checks of P10 and the output comparison of P8;
the per-layer reading is this skill's). Layer 1 handles failures Nextflow
sees; layer 2 catches tasks that never produced a completion record (lost,
never scheduled, or dropped) and cannot catch a task whose wrapper falsely
reported success, which is why output comparison (P8, Step 2) stays in place;
layer 3 handles failures Nextflow never sees; layer 4 turns a walltime kill
into an ordinary failure.

How to verify. Inject a non-zero exit in one task and confirm the run aborts
after the retry budget. Drop one completion record with a test config, for
example `withName: LASTZ { errorStrategy = { task.index == 3 ? 'ignore' : 'retry' } }`,
and confirm the integrity error fires. Pause the main job on a development run
and confirm the watchdog logs the stall and performs one cancel-and-resume.
Run one task with a deliberately short walltime and confirm no partial output
remains and the task is recorded as failed.

Evidence from the case study. Bug 1 (below) illustrates why retry policies
have to be combined with return-code and output checks. The watchdog recovered
an amphibian run of approximately 40,000 tasks that stalled during Slurm
controller communication failures in production.

## P8: Parity testing for divergent code paths

Anti-pattern. A pipeline that branches behavior by input size, file format, or
version exercises the rare branch only on rare inputs. Bugs in the rare branch
surface for the first time on the first slow run that triggers it.

Recommendation. For any code-path divergence introduced for an edge case, add
a CLI flag that forces the rare path on inputs small enough for tight feedback
loops, and pair it with a small comparator that quantifies any divergence
between the two paths' final outputs (overlap matching on the alignment-bucket
key rather than exact equality, since the rare branch may legitimately drift
on shared upstream tool internals). Mark the flag as a debugging option so it
does not appear in `params.json`, which stays reserved for scientific
parameters, but is recognized by the schema validator.

Mechanism. The flag converts a code path that would otherwise be exercised
only on roughly 40 GB genomes into one that runs on a small genome pair in
minutes. Bugs in the rare branch get the same feedback loop as bugs in the
common branch, and the comparator turns "it ran" into a number.

How to verify. The flag is declared in `nextflow_schema.json` and absent from
`params.json`. Two runs on the small input, with and without the flag, finish
in minutes, and the comparator reports matched and missing counts, the score
distribution against baseline, and boundary proximity.

Evidence from the case study. The pipeline supports two `.2bit` format
versions: V0 (32-bit offsets, the default, read natively by LASTZ) and V1
(64-bit offsets, required for genomes over 4 GB, not readable by LASTZ
directly). The reader path branches on detected version. The `--force_long_2bit`
flag forces the V1 path on small inputs; `standalone_scripts/compare_chains.py`
reports matched and missing chains, score distribution, and
target-partition-boundary proximity. The flag caught Bug 3 (below) on a small
genome before any production-scale run. On the tailed frog versus chicken
reference, the V0 path reproduces upstream chain for chain (643,861 chains on
both sides); the V1 path produces 642,243 chains, and 714 baseline chains
(about 0.11 percent) lack an overlap match, concentrated in the low-score
tail, with none within 10 kb of any target-partition boundary. This is
consistent with differences in LASTZ's handling of `.2bit` and FASTA input,
but the comparison alone does not establish the cause.

## P9: Audit parameters during migration

Anti-pattern. Long-lived pipelines accumulate CLI flags that no tool invocation
consumes; users may set them without observable effect.

Recommendation. Cross-check every CLI parameter accepted by the legacy
interface against actual tool invocations across every stage. The migration
is the natural moment to surface and remove dead flags.

Mechanism. The P4 separation makes visible which parameters reach which
layer, so a parameter with no consumer stands out as a row with no invocation.

How to verify. A table maps every legacy parameter to a command line, a
config key, or "no consumer". The new interface omits every "no consumer" row
and the change log lists them.

Evidence from the case study. The audit found three dead parameters upstream
(`--seq1_limit`, `--seq2_limit`, `--fill_chain_min_score`); the refactored
pipeline omits them.

## P10: Recognize the silent-failure construction kit

Anti-pattern. Calling `subprocess.call(...)` without checking its return
code, combined with workflow-level `optional: true` outputs, can hide
failures. A wrapper can propagate a tool's non-zero return code, and Nextflow
can reject a missing required output; omitting both checks lets the failure
pass through both layers. The wrapped tool exits non-zero, `subprocess.call`
returns the exit code, the wrapper ignores it and exits zero, Nextflow records
task success, and the absence of the expected file is permitted by
`optional: true`. The run completes with missing data and no error trail.

Observability dimension. When a Python wrapper dispatches multiple tool
invocations inside one Nextflow task, those invocations share one
`stdout`/`stderr` pair and one task status, so a swallowed failure is
obscured in the task-level record. P2's one-process-per-tool structure
restores the layered observability Nextflow and Slurm provide by default.

Recommendation. Always check return codes when wrapping shell calls. Reserve
`optional: true` for outputs that are genuinely optional in the science (a
stage that emits a side-channel report only under specific conditions), not
for "the tool sometimes fails to write this".

Mechanism. Two independent checks each stop the failure; removing both is what
lets it through. Keeping either restores an error trail, keeping both gives a
task-level failure that P7 can retry or abort on.

How to verify. Every `subprocess.call`, `os.system`, or shell pipeline either
checks its return code or is replaced by `subprocess.run(..., check=True)`.
Every `optional: true` is justified in a comment by the science. A forced tool
failure on one task fails that task.

Evidence from the case study. Bug 1 (below): a latent upstream
filename-length bug silently omitted BULK-partition alignments when wrappers
ignored return codes (the paper cites Bug 1 as an instance of this failure
mode in legacy code); measured coverage loss was about 23 percent in one
amphibian sample.

## Synthesis: the paper's checklist

| # | Practice |
|---|---|
| P1 | Decompose Python orchestration into native channels. |
| P2 | One process per tool; group into subworkflows by stage. |
| P3 | Backward-compatible legacy entry point. |
| P4 | Separate scientific from infrastructure parameters. |
| P5 | Containerize with dual conda and container directives. |
| P6 | HPC-aware overlay on nf-core defaults: backfill-fit per-task-job sizing, `process.array`, walltime partition routing, `check_max()`, Slurm controller and submission-rate mitigations, and a pipeline-level data-prep cache for many-task steps. |
| P7 | Strict-by-default `errorStrategy`, post-stage integrity-check assertion, an out-of-band watchdog for stalled main jobs, and walltime-signal trapping for graceful per-task-job termination. |
| P8 | A parity-testing CLI option for any divergent code path. |
| P9 | Audit CLI parameters during migration; remove dead flags. |
| P10 | Recognize and refuse the `subprocess.call` plus `optional: true` silent-failure construction kit. |

## The three-part engineering discipline

The paper's refactor was done with heavy use of AI coding assistants (Claude
Code as the primary assistant, Qwen3 to cross-check alternative
implementations), and the discipline below is what the authors used to check
correctness. They report the process without evaluating the tools, and they
did not measure a productivity gain or a change in defect frequency. The
discipline applies equally to human-written code.

1. Pre-specification from observation. Before any code generation, build and
   record a change list from direct observation of the original pipeline on
   real data. The record has to be durable and predate the refactor; in the
   case study it was the 2025 operational paper, public bug and improvement
   requests filed upstream, and a deployment-recipe repository. The record is
   the reference for reviewing whether a change addressed the intended
   problem.
2. Characterization testing with tight output comparison. Capture a reference
   output on a small but realistic input and compare it with the refactored
   output: byte equivalence where appropriate, sorted records where order can
   vary, and a domain comparator (here, overlap-based chain matching) where
   legitimate drift is expected.
3. Human review of every generated change. Humans reviewed all code changes,
   the suggestions from AI review, and the test results, and ran the tool
   before and after modifications. Disagreement between the two models
   prompted examination of the assumptions behind the proposals.

The working cycle: record an observed problem and intended change, implement
and review the change, run the before-and-after comparisons, investigate
discrepancies before accepting the result.

The three bugs, each told once:

- Bug 1 (found by characterization testing; legacy code). A latent upstream
  filename-length bug could silently omit BULK-partition alignments when
  wrappers ignored return codes. Per-target-chromosome comparisons exposed
  missing chains for small scaffolds. Manual before-and-after comparison
  against the input data measured about 23 percent alignment-coverage loss in
  one amphibian sample. Lesson: output comparison has to accompany code review
  and explicit error handling.
- Bug 2 (scoped by pre-specification). Large-genome `.2bit` support was a
  known upstream limitation (issue 56). Producing a 64-bit V1 file with
  `faToTwoBit -long` required corresponding reader support. Recording the
  issue before implementation kept both the writer and reader changes in
  scope, including preservation of the existing V0 path.
- Bug 3 (found by the parity flag and by review of the failure; the paper
  gives it as its example under human review of AI-made changes without
  stating who wrote the attempted fix). An attempted
  solution to Bug 2 extracted V1 input to FASTA but retained LASTZ's
  `<file>/<seqname>` selector, which applies to `.2bit` input. The forced V1
  test on a small input failed because LASTZ treated the FASTA argument as a
  literal file path. Review of that failure led to correcting the command
  builder before any large-genome run.

## What the case study measured

Three configurations: Original (upstream Python-orchestrated joblists, no job
array, no container); Original + Job Array (upstream with `process.array` and
the best-practice configuration of the authors' prior work); and the nf-core
refactor (run with `-profile apptainer,slurm`). The Nextflow executor settings
(`pollInterval`, `queueSize`, `submitRateLimit`, `exitReadTimeout`,
`killBatchSize`) were identical across the three. Phoenix `public` partition:
three sample-pair blocks, each a distinct target-query pair, the three
configurations run concurrently with randomized submission order (N = 3 per
configuration), competing with each other and with other users; full-pipeline
walltime; 24 hour observation cap. Dev (private single-user cluster, same
`SchedulerParameters` as Phoenix): one run per configuration (N = 1),
sequential, same sample pair, walltime to LASTZ completion only. All inputs
were below the 4 GB threshold (V0 path). Walltimes are from logged timestamps.

| Run | Original | Original + Job Array | Refactor |
|---|---|---|---|
| Phoenix block 1 (full pipeline, h) | 24 (includes supervised rerun) | 6.912 (includes supervised rerun) | 4.370 |
| Phoenix block 2 (full pipeline, h) | at least 24 (unfinished at cap) | 5.120 (includes supervised rerun) | 2.716 |
| Phoenix block 3 (full pipeline, h) | at least 24 (unfinished at cap) | 12.766 (includes supervised rerun) | 5.550 |
| Dev, N = 1 (through LASTZ, h) | 2.752 | 3.227 | 2.436 |

Findings, as the paper states them:

- The refactor had the shortest completion time in every Phoenix block and
  reached LASTZ completion fastest on Dev. Several changes separate the full
  refactor from the other configurations, so its results cannot be attributed
  to a single implementation change.
- Job arrays substantially reduced distinct `sbatch` submissions (tasks in an
  array share a base job ID) but did not consistently shorten execution time:
  on Dev the array patch submitted fewer jobs and took longer than Original to
  reach LASTZ completion. The study does not isolate the cause.
- The refactor makes more submissions than Original + Job Array, consistent
  with its finer process decomposition (P2), while both remain far below
  Original.
- On Dev, Original produced higher main-scheduler cycle and submission-RPC
  rates during its main submission wave than the array-enabled
  configurations; polling rates were generally similar. The measurements
  support reduced submission traffic but do not establish that arrays
  eliminate polling or that polling dominates controller cost.
- Limits: one site, one workflow, three sample pairs, all on the V0 path;
  Phoenix timings include contention; Dev timings end at LASTZ; N = 1 on Dev
  does not estimate run-to-run variability. Other sites and schedulers need
  separate measurement.

The paper's Discussion adds that partition routing, Fairshare behavior, and
controller settings depend on the scheduler and site; sites adopting
nf-core-style pipelines should budget time to adapt them.

## Site context: how much Slurm tuning varies

The paper's `SchedulerParameters` table for its two production clusters, as an
example of why site limits are asked for rather than assumed (Dev used the
Phoenix values; shared settings such as `bf_window=43200`, `bf_interval=30`,
and `enable_user_top` omitted):

| Parameter | Sol (general purpose) | Phoenix (high throughput) |
|---|---|---|
| `bf_max_job_assoc` | 25 | 2600 |
| `bf_max_job_user` | 50 | not set |
| `bf_max_job_start` | not set | 1300 |
| `bf_max_job_test` | 150,000 | 200,000 |
| `max_rpc_cnt` | 200 | 450 |
| `bf_yield_rpc_cnt` | 150 | not set |
| `preempt_strict_order` | not set | set |

`max_rpc_cnt` controls when scheduling yields to RPC traffic; it does not set
the controller's RPC thread limit. The companion HPCSYSPROS'26 study adds that
Phoenix runs `MaxArraySize=300000` and `MaxJobCount=550000`, and that the
configured array batch size has to fit within `MaxArraySize`.

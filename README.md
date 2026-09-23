<p align="center">
  <img src="logo.png" alt="WfTune logo" width="160">
</p>

<h1 align="center">WfTune</h1>

<p align="center">
  <strong>Benchmarking scientific workflow deployment on HPC for performance and scheduler impact.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="License: MIT"></a>
  <a href="#requirements"><img src="https://img.shields.io/badge/Python-3.9%2B-3776AB.svg?style=flat-square" alt="Python: 3.9 or newer"></a>
  <a href="#supported-execution-paths"><img src="https://img.shields.io/badge/Scheduler-Slurm-008080.svg?style=flat-square" alt="Scheduler: Slurm"></a>
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> &middot;
  <a href="#supported-execution-paths">Execution paths</a> &middot;
  <a href="#preparing-a-real-campaign">Campaign guide</a> &middot;
  <a href="#analysis">Analysis</a> &middot;
  <a href="#research-provenance">Research</a>
</p>

---

## Overview

WfTune measures how a workflow deployment affects both user-visible completion
time and the Slurm control plane. It provides a clean-start collection
protocol, workload adapters, controller-side monitoring, campaign auditing,
and analysis for comparing workflow managers and dispatch strategies without
assuming that one strategy is best at every site.

> [!NOTE]
> This repository contains tools, configuration templates, and deterministic
> synthetic fixtures. It intentionally contains **no real campaign data,
> scientific inputs, workflow outputs, credentials, or site configuration**.

**Start with the [synthetic quick start](#quick-start)** to explore the analysis
path without Slurm, or use the [campaign guide](#preparing-a-real-campaign) to
prepare collection with your site administrator.

## What WfTune measures

The primary measurements share one lifecycle across all supported treatments:

| Measurement | Definition |
| :--- | :--- |
| **Workflow completion time** | Allocation-inclusive walltime from the controller's pre-submission timestamp to a declared scientific endpoint. |
| **Scheduler impact** | Total Slurm RPC count attributed to the benchmark user between root-observed `sdiag` boundaries. |
| **Controller-processing time** | Processing time for that user's RPCs, reported as sensitivity context. |

Low-rate cluster-global `sdiag` samples describe the conditions observed during
a run. They are contextual evidence, not automatically attributed background
load. Semantic validation, frozen manifests, configuration hashes, and a
campaign audit keep incomparable or incomplete trials out of the analysis.

## Supported execution paths

| Workflow manager | Native Slurm | Job arrays | HyperQueue | Flux | Local in allocation |
| :--- | :---: | :---: | :---: | :---: | :---: |
| Nextflow | Yes | Yes | Yes | Yes | Yes |
| Snakemake | Yes | Yes | — | — | — |

**Nextflow.** `native` submits eligible tasks individually, `jobarray` uses
Nextflow's Slurm-array support, `hyperqueue` and `flux` dispatch inside fresh
enclosing allocations, and `local` executes inside one Slurm allocation.

**Snakemake.** The current adapters use the official Slurm executor plugin.
The array treatment additionally enables its job-array option. WfTune does not
claim Snakemake support for HyperQueue, Flux, or local execution yet.

## Requirements

| Component | Requirements |
| :--- | :--- |
| Collection | Linux; Slurm with per-user `sdiag` statistics; Bash 4.4 or newer; Python 3.9 or newer; root access on the physical controller. |
| Nextflow treatments | Nextflow 24.04 or newer. HyperQueue and Flux are needed only for their respective treatments. |
| Snakemake treatments | Snakemake with the official Slurm executor and jobstep plugins. |
| Analysis | The pinned packages in [`requirements-analysis.txt`](requirements-analysis.txt). |

<a id="synthetic-smoke-test"></a>

## Quick start

Run a synthetic smoke test from a local checkout. The fixture generator
produces fabricated Slurm records and a synthetic task trace, so **no live
Slurm access is required**.

> [!IMPORTANT]
> Synthetic values exercise the audit and plotting path only. They are not
> scientific observations and must never be reported as benchmark results.

### 1. Create an analysis environment

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements-analysis.txt
```

### 2. Generate and audit a fixture

Create one synthetic replicate for two example clusters:

```bash
python examples/synthetic/make_fixture.py /tmp/wftune-example --reps 1

python analysis/audit_campaign.py /tmp/wftune-example \
  --through-rep 1 \
  --venue reference \
  --venue shared \
  --require-secondary-context
```

### 3. Summarize and visualize

```bash
python analysis/summarize_results.py \
  /tmp/wftune-example /tmp/wftune-summary \
  --through-rep 1 \
  --venue reference \
  --venue shared

python analysis/plot_walltime_stress.py \
  /tmp/wftune-example /tmp/wftune-walltime-rpc.png \
  --through-rep 1 \
  --venue reference \
  --venue shared
```

The summary is written to `/tmp/wftune-summary` and the figure to
`/tmp/wftune-walltime-rpc.png`. See the
[synthetic fixture guide](examples/synthetic/README.md) for scope and safeguards.

## Collection and trust boundary

![WfTune trust boundary: three collection roles write immutable evidence for read-only offline analysis.](docs/images/wftune-trust-boundary.png)

[View the editable vector diagram](docs/images/wftune-trust-boundary.svg).

WfTune separates controlled site actions, measured workflow demand, and
out-of-band observation. Each role writes distinct evidence to an immutable run
tree; validation and analysis then run offline without live Slurm access. This
keeps monitoring traffic out of the benchmark identity's per-user RPC delta and
makes incomplete evidence a hard analysis failure.

## Preparing a real campaign

> [!WARNING]
> Real collection is not a one-command laptop benchmark. It observes a Slurm
> controller and resets the dedicated benchmark association's Fairshare usage.
> **Coordinate with the site administrator before collecting data.**

### Preparation checklist

1. Install a frozen WfTune checkout at a path visible from the physical
   `slurmctld` host and the main compute allocations.
2. Select a dedicated benchmark user and account. Do not share that account
   with unrelated jobs during collection.
3. Copy and fill the appropriate templates outside the repository:
   - **Nextflow:** [controller environment](examples/controller.env.example)
     and [pipeline environment](examples/pipeline.env.example).
   - **Snakemake:**
     [controller environment](examples/controller.snakemake.env.example),
     [pipeline environment](examples/snakemake.pipeline.env.example),
     [site profile](examples/snakemake-site-profile.yaml.example), and
     [workflow profile](examples/snakemake-workflow-profile.yaml.example).
4. Supply a workflow-specific semantic validator and immutable input,
   pipeline-source, configuration, and container manifests.
5. Install the controller environment and validator as root-owned,
   group/world-nonwritable files.
6. Run preflight on the physical controller before collecting anything.

### Run preflight and collect

**Nextflow**

```bash
sudo bash controller/check_env.sh /etc/wftune-nextflow.env
sudo bash controller/run_rep.sh \
  /etc/wftune-nextflow.env cluster-a 1 native,jobarray,hyperqueue,flux
```

**Snakemake**

```bash
sudo bash controller/check_env.sh /etc/wftune-snakemake.env
sudo bash controller/run_rep.sh \
  /etc/wftune-snakemake.env cluster-a 1 native,jobarray
```

Repeat with positive block indices for independent replicates. Only one
treatment may run at a time for the same cluster/account/campaign; the shared
lock enforces that rule. Analysis discovers `ROOT/<venue>/repN` trees when no
`--venue` is supplied; pass it explicitly to select a subset.

For a step-by-step alternative, see the
[manual Nextflow procedure](controller/manual/README.md).

## Data separation

**Keep every real data root outside the source checkout.** The controller
template requires separate locations for:

| Environment variable | Purpose |
| :--- | :--- |
| `WMSbench_MONITOR_ROOT` | Root-owned monitoring tree. |
| `WMSbench_PIPELINE_ROOT` | Workflow work, results, traces, and logs. |
| `WMSbench_LOCK_ROOT` | Cluster/account campaign lock. |

The monitoring tree retains the minimum evidence needed for reproducible
analysis: immutable `run.json`, boundary and periodic `sdiag` snapshots, the
normalized final trace/report, lifecycle handoffs, validation output, and
configuration hashes. Large work directories and scientific results remain in
the separate pipeline tree.

The repository's [`.gitignore`](.gitignore) excludes common run records and
data-root names, but that is only a last guardrail. Before publishing a dataset,
review it for usernames, cluster names, absolute paths, proprietary workflow
inputs, and site-sensitive scheduler information.

## Analysis

### Audit the evidence

Audit each monitor root before producing a result:

```bash
python analysis/audit_campaign.py /path/to/monitor-root \
  --through-rep 3 --venue cluster-a \
  --backends native,jobarray,hyperqueue,flux \
  --require-secondary-context
```

### Summarize and plot

Create tables and the walltime/RPC figures:

```bash
python analysis/summarize_results.py \
  /path/to/monitor-root /path/to/output \
  --through-rep 3 --venue cluster-a \
  --backends native,jobarray,hyperqueue,flux

python analysis/plot_walltime_stress.py \
  /path/to/monitor-root /path/to/output/walltime-rpc.png \
  --through-rep 3 --venue cluster-a \
  --backends native,jobarray,hyperqueue,flux
```

### Compare workflow managers

Cross-WMS analysis validates each WMS root independently and joins only the
allocation-inclusive walltime and total attributable RPC count:

```bash
python analysis/plot_cross_wms.py \
  --series Nextflow=/path/to/monitor/nextflow \
  --series Snakemake=/path/to/monitor/snakemake \
  --venue cluster-a --through-rep 3 \
  --backends native,jobarray \
  --out /path/to/output/cross-wms.pdf \
  --csv /path/to/output/cross-wms.csv
```

> [!IMPORTANT]
> Analysis refuses missing, overlapping, censored, corrupt, or
> configuration-drifted runs. It does not generate substitute observations.

## Energy tools

The [`energy/`](energy/) directory contains standalone samplers for node-local RAPL
counters and site-provided PDU power readings, plus a calibration helper. Use
them **only on exclusive nodes with an approved reservation**; whole-node
energy cannot be attributed to one workflow when unrelated tenants share the
node. See the [energy tools guide](energy/README.md).

## Operational safety

- **Privileged operations.** Controller collection and Fairshare reset run as
  root on the physical `slurmctld` host. Review the scripts with the site
  administrator first.
- **Measurement integrity.** Never poll Slurm as the benchmark user during the
  measured window; those calls would inflate the same per-user RPC counter
  being measured.
- **Account isolation.** Use a dedicated benchmark account and allow its jobs
  to drain before the closing boundary.
- **Secrets.** Do not place secrets in controller templates or commit filled
  `.env` files.
- **Scientific validity.** Treat generated plots as results only after the
  strict audit passes on real, semantically validated observations.

## Repository layout

| Directory | Contents |
| :--- | :--- |
| [`analysis/`](analysis/) | Campaign audit, summaries, plots, and cross-WMS comparison. |
| [`config/`](config/) | Reusable Nextflow backend and trace configuration. |
| [`controller/`](controller/) | Root-side preflight, collection, finalization, and manual runner. |
| [`energy/`](energy/) | Standalone RAPL and pluggable PDU sampling/calibration tools. |
| [`examples/`](examples/) | Slurm entry points and fill-in configuration templates. |
| [`monitor/`](monitor/) | Low-rate `sdiag` and Fairshare capture helpers. |

The `WMSbench_*` environment-variable prefix is retained for compatibility
with the original research harness. Public schemas and new internal symbols
use the `wftune` namespace.

## Research provenance

WfTune grows out of the measurement methodology and case-study artifacts in
the [Slurm-Stress-SC26](https://github.com/NilaBlueshirt/Slurm-Stress-SC26)
repository.

**Related paper:** [*Balancing Workload Performance and Slurm Stress: Four
Nextflow Deployment Strategies*](https://arxiv.org/abs/2608.13824), the original
four-backend study.

## License

WfTune is released under the [MIT License](LICENSE).

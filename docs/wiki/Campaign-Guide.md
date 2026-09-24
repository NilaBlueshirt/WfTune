# Campaign guide

Use this guide with your site administrator to prepare and collect real
measurements. Check the [requirements](https://github.com/NilaBlueshirt/WfTune/wiki/Getting-Started#requirements)
and [execution paths](https://github.com/NilaBlueshirt/WfTune/wiki/Execution-Paths) before configuring a campaign.
Run the commands below from the repository root.

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
   - **Nextflow:** [controller environment](https://github.com/NilaBlueshirt/WfTune/blob/main/examples/controller.env.example)
     and [pipeline environment](https://github.com/NilaBlueshirt/WfTune/blob/main/examples/pipeline.env.example).
   - **Snakemake:**
     [controller environment](https://github.com/NilaBlueshirt/WfTune/blob/main/examples/controller.snakemake.env.example),
     [pipeline environment](https://github.com/NilaBlueshirt/WfTune/blob/main/examples/snakemake.pipeline.env.example),
     [site profile](https://github.com/NilaBlueshirt/WfTune/blob/main/examples/snakemake-site-profile.yaml.example), and
     [workflow profile](https://github.com/NilaBlueshirt/WfTune/blob/main/examples/snakemake-workflow-profile.yaml.example).
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
[manual Nextflow procedure](https://github.com/NilaBlueshirt/WfTune/wiki/Manual-Nextflow-Runner).

## Version recording

The [`VERSION`](https://github.com/NilaBlueshirt/WfTune/blob/main/VERSION) file
at the harness root names the installed WfTune release as one SemVer string,
such as `0.1.0`. A pre-release suffix such as `0.2.0-dev.1` marks a checkout
between releases; build metadata (`+...`) is rejected. Preflight requires the
file to be root-owned, not group/world-writable, not a symlink, and readable by
the benchmark user, whose batch job also reads it.

Each trial records the version twice: the controller writes `wftune_version` to
`trial.env` at trial start, and the batch job writes the version it reads on the
compute node to `handoff/pipeline_contract.env`. The collector refuses a run
whose two values differ, which catches a different WfTune copy at the same path
on the compute nodes, and stores the agreed value in `run.json` as
`"wftune": {"version": "0.1.0"}`.

Before each trial, the automated and manual runners warn when runs already
recorded for the venue carry another version, or none. The trial still runs,
but [analysis](https://github.com/NilaBlueshirt/WfTune/wiki/Analysis#wftune-versions)
rejects a campaign that mixes versions unless explicitly overridden. Change the
installed release only between campaigns, and collect the new campaign in a
fresh monitoring root or under a new venue label.

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

The repository's [`.gitignore`](https://github.com/NilaBlueshirt/WfTune/blob/main/.gitignore) excludes common run records and
data-root names, but that is only a last guardrail. Before publishing a dataset,
review it for usernames, cluster names, absolute paths, proprietary workflow
inputs, and site-sensitive scheduler information.

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

## After collection

Follow the [analysis guide](https://github.com/NilaBlueshirt/WfTune/wiki/Analysis) to audit the evidence, generate
summaries, and compare workflow managers.

# Getting started

Try WfTune's analysis workflow with a deterministic synthetic fixture. You can
run this locally without Slurm or access to a cluster.

## Requirements

For the local quick start, use Python 3.9 or newer and the pinned analysis
packages below. Slurm and controller access are needed only for real collection.

| Component | Requirements |
| :--- | :--- |
| Collection | Linux; Slurm with per-user `sdiag` statistics; Bash 4.4 or newer; Python 3.9 or newer; root access on the physical controller. |
| Nextflow treatments | Nextflow 24.04 or newer. HyperQueue and Flux are needed only for their respective treatments. |
| Snakemake treatments | Snakemake with the official Slurm executor and jobstep plugins. |
| Analysis | The pinned packages in [`requirements-analysis.txt`](https://github.com/NilaBlueshirt/WfTune/blob/main/requirements-analysis.txt). |

## Get the source

```bash
git clone https://github.com/NilaBlueshirt/WfTune.git
cd WfTune
```

Run all commands below from the repository root.

## Synthetic quick start

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
`/tmp/wftune-walltime-rpc.png`.

## About the synthetic fixture

`make_fixture.py` creates a deterministic, fabricated WfTune monitoring tree
for smoke-testing the audit, summary, and plotting commands without Slurm.

The fixture includes synthetic task traces, lifecycle records, semantic
validation markers, and `sdiag` text for five backends on two fictional cluster
labels. It contains no observations copied from a real campaign. Pass
`--wms snakemake` to generate a second, independently labeled fixture for
smoke-testing the cross-WMS join; this is still parser test data, not a model of
Snakemake performance.

Each fabricated `run.json` records the checkout's
[`VERSION`](https://github.com/NilaBlueshirt/WfTune/blob/main/VERSION). Pass
`--wftune-version [REP=]VERSION` to override it for every replicate or for one,
or use `unrecorded` to omit it, as a run from before version recording would.
For example, this campaign mixes versions, so the audit rejects it:

```bash
python examples/synthetic/make_fixture.py /tmp/wftune-mixed --reps 2 \
  --wftune-version 2=unrecorded
```

The generated numbers are intentionally plausible enough to exercise figures,
but they are not evidence and must not be reported, compared, or published as
benchmark results.

## Run the tests

The unit tests run offline and need neither Slurm nor root access. Run them
from the repository root with the analysis environment active:

```bash
python -m unittest discover -s tests
```

Tests of the Bash helpers are skipped when `bash` is not on the `PATH`.

## Next steps

- Learn how the metrics are defined in the [measurement protocol](https://github.com/NilaBlueshirt/WfTune/wiki/Measurement-Protocol).
- Prepare real collection with the [campaign guide](https://github.com/NilaBlueshirt/WfTune/wiki/Campaign-Guide).
- Explore campaign and cross-workflow comparisons in the [analysis guide](https://github.com/NilaBlueshirt/WfTune/wiki/Analysis).

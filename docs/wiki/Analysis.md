# Analysis

Analyze an existing monitoring tree offline, using the packages in
[`requirements-analysis.txt`](https://github.com/NilaBlueshirt/WfTune/blob/main/requirements-analysis.txt). Run these commands
from the repository root with your analysis environment activated.
For a complete example without real data, start with the
[synthetic quick start](https://github.com/NilaBlueshirt/WfTune/wiki/Getting-Started).

## Audit the evidence

Audit each monitor root before producing a result:

```bash
python analysis/audit_campaign.py /path/to/monitor-root \
  --through-rep 3 --venue cluster-a \
  --backends native,jobarray,hyperqueue,flux \
  --require-secondary-context
```

## Summarize and plot

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

## Compare workflow managers

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
> configuration-drifted runs, and campaigns whose runs carry different WfTune
> versions. It does not generate substitute observations.

## Selecting the campaign scope

Analysis discovers `ROOT/<venue>/repN` trees when no `--venue` is supplied;
pass it explicitly to select a subset. Match `--backends` to the treatments
collected for the campaign and `--through-rep` to its replicate coverage.

## WfTune versions

Every run in the selected campaign must carry the same
[recorded WfTune version](https://github.com/NilaBlueshirt/WfTune/wiki/Campaign-Guide#version-recording).
Runs collected before version recording have no `wftune` object in `run.json`;
they remain readable and count as one more version, "unrecorded", so they
cannot be mixed with versioned runs either.

To analyze a mixed campaign deliberately, add `--allow-version-drift`:

```bash
python analysis/audit_campaign.py /path/to/monitor-root \
  --through-rep 3 --venue cluster-a --allow-version-drift
```

`summarize_results.py` and the campaign plotting commands accept the same flag.
With it, the audit admits the campaign but reports `primary_pass: false`, and
its report lists `observed_wftune_versions` and
`unrecorded_wftune_version_count`.

`plot_cross_wms.py` checks each series on its own, so the Nextflow and
Snakemake roots may carry different versions. The flag admits a series whose
own runs are mixed and notes it on standard error.

Per-run tables, including the audit's runs CSV and the summary's runs table,
have a `wftune_version` column that is empty for unrecorded runs.

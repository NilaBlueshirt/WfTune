# Execution paths

Check the [requirements](https://github.com/NilaBlueshirt/WfTune/wiki/Getting-Started#requirements)
for the tools needed by each treatment.

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

## Choosing a comparison

Use the same scientific endpoint and frozen inputs across treatments. Compare
backends within one workflow manager, or select the shared `native` and
`jobarray` treatments for a Nextflow/Snakemake comparison.

See the [campaign guide](https://github.com/NilaBlueshirt/WfTune/wiki/Campaign-Guide) for collection and the
[analysis guide](https://github.com/NilaBlueshirt/WfTune/wiki/Analysis#compare-workflow-managers) for cross-WMS analysis.

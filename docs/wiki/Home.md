# WfTune documentation

WfTune benchmarks scientific workflow deployment on Slurm, measuring both
workflow completion time and scheduler impact. This wiki covers local analysis,
real campaign collection, and the evidence needed to compare treatments.

## Start here

| Your goal | Guide |
| :--- | :--- |
| Try the analysis without a cluster | [Getting started](https://github.com/NilaBlueshirt/WfTune/wiki/Getting-Started) |
| Check workflow managers and backends | [Execution paths](https://github.com/NilaBlueshirt/WfTune/wiki/Execution-Paths) |
| Understand the metrics and collection roles | [Measurement protocol](https://github.com/NilaBlueshirt/WfTune/wiki/Measurement-Protocol) |
| Prepare and run a real campaign | [Campaign guide](https://github.com/NilaBlueshirt/WfTune/wiki/Campaign-Guide) |
| Audit, summarize, and plot results | [Analysis](https://github.com/NilaBlueshirt/WfTune/wiki/Analysis) |
| Cite the research behind WfTune | [Citation](https://github.com/NilaBlueshirt/WfTune/wiki/Citation) |

## Additional guides

- [Manual Nextflow runner](https://github.com/NilaBlueshirt/WfTune/wiki/Manual-Nextflow-Runner): operate each collection transition by hand.
- [Energy tools](https://github.com/NilaBlueshirt/WfTune/wiki/Energy-Tools): standalone RAPL/PDU sampling and calibration.
- [Repository layout](https://github.com/NilaBlueshirt/WfTune/wiki/Repository-Layout): find the scripts, configurations, and templates.

> **Before collecting:** real campaigns require coordination with the site
> administrator and root access on the physical Slurm controller. Start with
> the synthetic quick start to explore the analysis locally.

The repository contains code, configuration templates, and synthetic fixtures.
Real campaign data, scientific inputs, workflow outputs, credentials, and site
configuration stay outside the source checkout. Synthetic fixtures exercise the
software; they are not benchmark results.

## Citation

See [Citation](https://github.com/NilaBlueshirt/WfTune/wiki/Citation) for the
research paper, copyable BibTeX and plain-text references, and project provenance.

[Source repository](https://github.com/NilaBlueshirt/WfTune) · [MIT license](https://github.com/NilaBlueshirt/WfTune/blob/main/LICENSE)

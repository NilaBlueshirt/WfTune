# WfTune

Offline analysis tools for [WfTune](https://github.com/NilaBlueshirt/WfTune)
campaigns. WfTune benchmarks scientific workflow deployment on Slurm by
measuring completion time alongside the demand each deployment places on the
scheduler.

This package audits, summarizes, and plots the evidence a WfTune campaign
collects. It never contacts Slurm and needs no special privileges. Collection
itself is administrator-managed and is distributed as the
[source repository](https://github.com/NilaBlueshirt/WfTune), not through this
package.

## Install

```bash
pip install wftune
```

WfTune requires Python 3.11 or newer.

## Try it with synthetic data

```bash
wftune demo /tmp/wftune-example
wftune audit /tmp/wftune-example --through-rep 1
wftune summarize /tmp/wftune-example /tmp/wftune-summary --through-rep 1
wftune plot walltime-stress /tmp/wftune-example figure.png --through-rep 1
```

`wftune demo` writes fabricated records for exercising the tools. They are not
benchmark results and must never be reported as such.

## Commands

| Command | Purpose |
| :--- | :--- |
| `wftune demo` | Generate a synthetic monitoring tree to try the tools. |
| `wftune audit` | Validate campaign evidence and write the audit report. |
| `wftune summarize` | Write the per-run, summary, and paired-ratio tables. |
| `wftune trace-resources` | Compute task resource metrics from Nextflow traces. |
| `wftune plot FIGURE` | Draw `walltime-stress`, `rpc-accumulation`, `sdiag-backends`, `cross-wms`, `single-run`, or `energy`. |

Run `wftune COMMAND --help` for a command's options. The
[analysis guide](https://github.com/NilaBlueshirt/WfTune/wiki/Analysis)
explains how to audit and compare a real campaign.

## Citation

The measurement methodology is described in a paper published at the SC26 HPC
Systems Professionals Workshop (HPCSYSPROS). See
[Citation](https://github.com/NilaBlueshirt/WfTune/wiki/Citation) for
references.

WfTune is released under the MIT License.

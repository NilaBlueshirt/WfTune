# Repository layout

| Directory | Contents |
| :--- | :--- |
| [`analysis/`](https://github.com/NilaBlueshirt/WfTune/tree/main/analysis/) | Campaign audit, summaries, plots, and cross-WMS comparison. |
| [`config/`](https://github.com/NilaBlueshirt/WfTune/tree/main/config/) | Reusable Nextflow backend and trace configuration. |
| [`controller/`](https://github.com/NilaBlueshirt/WfTune/tree/main/controller/) | Root-side preflight, collection, finalization, and manual runner. |
| [`energy/`](https://github.com/NilaBlueshirt/WfTune/tree/main/energy/) | Standalone RAPL and pluggable PDU sampling/calibration tools. |
| [`examples/`](https://github.com/NilaBlueshirt/WfTune/tree/main/examples/) | Slurm entry points and fill-in configuration templates. |
| [`monitor/`](https://github.com/NilaBlueshirt/WfTune/tree/main/monitor/) | Low-rate `sdiag` and Fairshare capture helpers. |
| [`tests/`](https://github.com/NilaBlueshirt/WfTune/tree/main/tests/) | Offline unit tests; no Slurm or root access needed. |

The [`VERSION`](https://github.com/NilaBlueshirt/WfTune/blob/main/VERSION) file
at the repository root names the WfTune release that every collected run
records.

The `WMSbench_*` environment-variable prefix is retained for compatibility
with the original research harness. Public schemas and new internal symbols
use the `wftune` namespace.

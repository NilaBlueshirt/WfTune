# Measurement protocol

The primary measurements share one lifecycle across all supported treatments:

| Measurement | Definition |
| :--- | :--- |
| **Workflow completion time** | Allocation-inclusive walltime from the controller's pre-submission timestamp to a declared scientific endpoint. |
| **Scheduler impact** | Total Slurm RPC count attributed to the benchmark user between root-observed `sdiag` boundaries. |
| **Controller-processing time** | Processing time for that user's RPCs, reported as sensitivity context. |

Low-rate cluster-global `sdiag` samples describe the conditions observed during
a run. They are contextual evidence, not automatically attributed background
load. Semantic validation, frozen manifests, configuration hashes, the recorded
WfTune version, and a campaign audit keep incomparable or incomplete trials out
of the analysis.

## Collection and trust boundary

![WfTune trust boundary: three collection roles write immutable evidence for read-only offline analysis.](https://raw.githubusercontent.com/NilaBlueshirt/WfTune/main/docs/images/wftune-trust-boundary.png)

[View the editable vector diagram](https://github.com/NilaBlueshirt/WfTune/blob/main/docs/images/wftune-trust-boundary.svg).

WfTune separates controlled site actions, measured workflow demand, and
out-of-band observation. Each role writes distinct evidence to an immutable run
tree; validation and analysis then run offline without live Slurm access. This
keeps monitoring traffic out of the benchmark identity's per-user RPC delta and
makes incomplete evidence a hard analysis failure.

## Evidence and validation

The monitoring tree retains immutable `run.json`, boundary and periodic
`sdiag` snapshots, the normalized final trace/report, lifecycle handoffs,
validation output, and configuration hashes. Workflow work directories and
scientific results live in a separate pipeline tree.

Before producing results, run the [campaign audit](https://github.com/NilaBlueshirt/WfTune/wiki/Analysis#audit-the-evidence).
For the collection prerequisites and data-root layout, see the
[campaign guide](https://github.com/NilaBlueshirt/WfTune/wiki/Campaign-Guide).

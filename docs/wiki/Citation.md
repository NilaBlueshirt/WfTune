# Citation

If you use WfTune in your research, cite the paper behind the part you use.
These blocks are ready to copy into a bibliography or reference list.

- **Measurement methodology:** the [HPCSYSPROS'26 paper](#measurement-methodology-hpcsyspros26).
- **The [`wms-hpc-refactor`](https://github.com/NilaBlueshirt/WfTune/tree/main/skill/wms-hpc-refactor) agent skill:**
  the [USRSE'26 paper](#refactoring-practices-usrse26).

## Measurement methodology (HPCSYSPROS'26)

**[Balancing Workload Performance and Slurm Stress: Four Nextflow Deployment Strategies](https://arxiv.org/abs/2608.13824)**
by Nil Tianchen Mu, William Dizon, Glen Otero, and Torey Battelle (2026).
Published at the HPC Systems Professionals Workshop (HPCSYSPROS) at SC26.

[arXiv](https://arxiv.org/abs/2608.13824) ·
[PDF](https://arxiv.org/pdf/2608.13824) ·
[DOI: 10.48550/arXiv.2608.13824](https://doi.org/10.48550/arXiv.2608.13824)

### BibTeX

```bibtex
@misc{mu2026balancing,
  title         = {Balancing Workload Performance and {Slurm} Stress: Four {Nextflow} Deployment Strategies},
  author        = {Mu, Nil Tianchen and Dizon, William and Otero, Glen and Battelle, Torey},
  year          = {2026},
  note          = {HPC Systems Professionals Workshop (HPCSYSPROS) at SC26},
  eprint        = {2608.13824},
  archivePrefix = {arXiv},
  primaryClass  = {cs.DC},
  doi           = {10.48550/arXiv.2608.13824},
  url           = {https://arxiv.org/abs/2608.13824}
}
```

### Plain text

```text
Mu, Nil Tianchen, William Dizon, Glen Otero, and Torey Battelle. (2026).
Balancing Workload Performance and Slurm Stress: Four Nextflow Deployment Strategies.
HPC Systems Professionals Workshop (HPCSYSPROS) at SC26.
arXiv:2608.13824 [cs.DC]. https://doi.org/10.48550/arXiv.2608.13824
```

## Refactoring practices (USRSE'26)

**[Ten Practices for Refactoring Scientific Pipelines to nf-core DSL2 on Shared Slurm HPC](https://doi.org/10.5281/zenodo.22921770)**
by Nil Tianchen Mu, William Dizon, Glen Otero, and Torey Battelle (2026).
Published at the US Research Software Engineering Conference 2026 (USRSE'26).

[Zenodo](https://zenodo.org/records/22921770) ·
[PDF](https://zenodo.org/records/22921770/files/USRSE26_paper_draft.pdf) ·
[DOI: 10.5281/zenodo.22921770](https://doi.org/10.5281/zenodo.22921770)

### BibTeX

```bibtex
@inproceedings{mu2026tenpractices,
  title     = {Ten Practices for Refactoring Scientific Pipelines to {nf-core} {DSL2} on Shared {Slurm} {HPC}},
  author    = {Mu, Nil Tianchen and Dizon, William and Otero, Glen and Battelle, Torey},
  booktitle = {US Research Software Engineering Conference 2026 (USRSE'26)},
  year      = {2026},
  publisher = {Zenodo},
  doi       = {10.5281/zenodo.22921770},
  url       = {https://doi.org/10.5281/zenodo.22921770}
}
```

### Plain text

```text
Mu, Nil Tianchen, William Dizon, Glen Otero, and Torey Battelle. (2026).
Ten Practices for Refactoring Scientific Pipelines to nf-core DSL2 on Shared Slurm HPC.
US Research Software Engineering Conference 2026 (USRSE'26).
Zenodo. https://doi.org/10.5281/zenodo.22921770
```

## Research provenance

WfTune grows out of the measurement methodology and case-study artifacts in
the [Slurm-Stress-SC26](https://github.com/NilaBlueshirt/Slurm-Stress-SC26)
repository. The HPCSYSPROS'26 paper reports the original four-backend Nextflow
study; the [execution guide](https://github.com/NilaBlueshirt/WfTune/wiki/Execution-Paths)
describes WfTune's current backend support.

The `wms-hpc-refactor` skill turns the USRSE'26 paper's ten practices into a
procedure for a coding agent. That paper's case study is the refactored
[make_lastz_chains](https://github.com/NilaBlueshirt/make_lastz_chains/tree/nf-core-refactor)
pipeline (branch `nf-core-refactor`).

For reproducibility, also report the WfTune version your runs recorded
(`wftune.version` in each `run.json`) or the Git commit used in your
experiments, and link to the [WfTune repository](https://github.com/NilaBlueshirt/WfTune).

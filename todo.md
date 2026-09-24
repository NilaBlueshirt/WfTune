# WfTune deployment and distribution plan

## Goal

Distribute WfTune as one project with two installation paths:

| Audience | Distribution | Installation model |
| --- | --- | --- |
| Cluster administrators collecting measurements | Versioned GitHub release bundle | Reviewed, root-owned deployment on the required hosts |
| Researchers auditing and analyzing results | Python package on PyPI | Isolated CLI installation with `pipx`, or `pip` in a virtual environment |

Publish the complete source release first, then introduce the analysis package.
Keep both artifacts under the same repository, version, and release notes once
the package exists. A stable public Python library API is not an initial goal.
The offline CLI and PyPI publication remain committed parts of this plan.

Use the existing [arXiv paper citation](README.md#research-provenance) for the
research. Zenodo archiving is optional and does not block either release path.

This document is a checklist for future work, not a statement that packaging,
publication, or cluster validation has already been completed.

## Future user experience

**Vision:** a researcher installs WfTune, explores a synthetic campaign, audits
its evidence, and produces a summary and figure without cloning the repository
or accessing a Slurm cluster.

The following is the target interface, not a set of commands available today.
Run installation in an activated virtual environment:

```bash
pip install wftune

wftune demo /tmp/wftune-example
wftune audit /tmp/wftune-example --through-rep 1
wftune summarize /tmp/wftune-example /tmp/wftune-summary --through-rep 1
wftune plot walltime-stress /tmp/wftune-example figure.png --through-rep 1
```

Alternatively, `pipx install wftune` will install the same CLI in an isolated
environment. Both installation paths depend on publication under the confirmed
PyPI package name.

| Command | Intended result |
| --- | --- |
| `wftune demo` | Generate a deterministic, clearly labeled synthetic monitoring tree, with one replicate by default so the sequence above works unchanged. |
| `wftune audit` | Validate campaign evidence, write the audit result, and return a nonzero exit code when validation fails. |
| `wftune summarize` | Write summary tables to the requested output directory. |
| `wftune plot walltime-stress` | Write the walltime/RPC figure to the requested file, including in headless environments. |

Synthetic outputs demonstrate the tool; they are never scientific observations.
Installing or running these offline commands must not submit jobs, reset
Fairshare, require root, or configure a collection service.

### How the plan delivers this interface

- **Phase 5** implements the exact command names, nesting, positional arguments,
  and options above as the initial CLI contract. A console-script entry point
  creates the `wftune` executable during installation.
- **Phase 6** uses the complete sequence as an end-to-end acceptance test,
  running the installed artifact outside the repository and checking its output.
- **Phase 7** publishes and verifies the package on PyPI so the installation
  command works without a local archive or repository URL.

Phases 1 and 2 establish naming, compatibility, and baseline tests. Phases 3 and
4 deliver the separate administrator deployment path; a live cluster deployment
is not required to use or test this offline interface.

## 1. Define the first release

- [ ] Choose the initial release version and document the versioning policy.
- [ ] Use one authoritative version source, such as a `VERSION` file, for
  release metadata, run records, Python package metadata, and CLI reporting.
- [ ] Define the supported CLI and monitoring-data schema compatibility policy;
  distinguish application versions from schema versions. Specify how older
  campaigns without WfTune provenance are handled; accepting unknown fields
  alone does not establish compatibility with a new auditor.
- [ ] Check availability of the intended PyPI distribution name `wftune` and
  recheck before publication. Confirm ownership through the first real upload
  in phase 7 before advertising installation; do not upload an empty placeholder.
- [ ] Confirm the repository owner and canonical URL before the first release
  and before configuring publishing integrations.
- [ ] Preserve the currently documented runtime requirements unless a separate,
  explicit support-policy change is agreed, including Python 3.9+ for collection.
- [ ] Define the analysis platform/Python test matrix separately from Linux-only
  controller deployment requirements. Use Python 3.12 for the current pinned
  reference analysis environment; broader support needs tested dependency
  combinations rather than assuming the current pins support newer Python.
- [ ] Keep Slurm, Nextflow, Snakemake, HyperQueue, Flux, and site configuration
  as externally managed prerequisites, not automatic package-install actions.
- [ ] Retain the [MIT license](LICENSE) and include its notice in each artifact.

**Exit criterion:** release scope, supported environments, artifact contents,
and compatibility expectations are documented.

## 2. Establish a reproducible source-release baseline

- [ ] Turn the [synthetic quick start](README.md#quick-start) into an automated
  smoke test: generate a fixture, audit it, summarize it, and produce a plot.
- [ ] Add an unprivileged integration test that generates raw synthetic run
  inputs, including `trial.env`, `status.env`, handoffs, and required evidence,
  runs [collect_run.py](controller/collect_run.py), then audits, summarizes, and
  plots its output. This must exercise the real collector without live Slurm;
  testing only fixture-authored `run.json` files can miss producer/consumer drift.
- [ ] Cover both Nextflow-labeled and Snakemake-labeled synthetic fixtures and
  the cross-WMS analysis path.
- [ ] Check exit codes and expected JSON/CSV contents and figure outputs, not
  just whether commands start successfully. Specify expected results
  independently of the collector and analysis implementation.
- [ ] Add negative cases for missing or corrupt evidence and configuration
  drift; confirm strict defaults still reject invalid campaigns.
- [ ] Test the documented handling of missing provenance in older campaigns
  and rejection of mixed WfTune release identities within a frozen campaign.
- [ ] Validate shell syntax with a supported Bash version without executing
  privileged collection or Fairshare reset.
- [ ] Add CI for the supported offline analysis environments. Keep live Slurm
  tests out of ordinary hosted CI.
- [ ] Preserve a pinned reference analysis environment using
  [requirements-analysis.txt](requirements-analysis.txt), run its CI job on
  Python 3.12, and record the exact interpreter and all resolved dependency
  versions for reproducibility.

**Exit criterion:** a clean checkout can reproduce the documented synthetic
outputs, and automated validation failures block release preparation.

## 3. Build and publish the first complete GitHub release

Version recording is already in progress. Complete and validate that work
before the first release and pilot campaign.

- [ ] Document archive contents and build from reviewed, tracked files at the
  selected commit, not arbitrary files in a developer's working directory.
- [ ] Include the controller, monitor, analysis, energy tools, configurations,
  examples, documentation, and license in a versioned deployment archive.
- [ ] Preserve the relative paths and script executable permissions required
  by the existing shell entry points. Set archive modes explicitly, for example
  with `git -c tar.umask=0022 archive --prefix=wftune-<version>/ <commit>`:
  directories and executable files should be `0755`, other files `0644`.
- [ ] Inspect recorded archive ownership and modes, including the top-level
  directory. An unprivileged extraction can mask unsafe archived modes through
  its umask; check archive headers or extract in an isolated root container.
- [ ] Exclude real campaign data, filled environment files, credentials, site
  configuration, caches, and local virtual environments. Use an explicit
  archive file list or `export-ignore` attributes for development-only files.
- [ ] Include release version and source-commit metadata that remain available
  after extraction without a `.git` directory, for example using `export-subst`.
- [ ] Finish recording the WfTune version and source commit through both
  automated and manual launchers, the collector, and per-run records. Have the
  campaign audit reject mixed release identities under the compatibility
  policy from phase 1, and test old and new records before deciding whether a
  schema version change is needed.
- [ ] Ship a per-file SHA-256 manifest for the deployed source and record its
  identity in provenance. Verify installed files against it during preflight
  to detect changes after extraction. Retain the archive checksum separately
  in deployment and campaign provenance to identify the downloaded artifact.
- [ ] Keep collection software/interpreter versions in collection provenance
  and record the analysis software/interpreter/dependency versions with analysis
  outputs; analysis may run later in a different environment.
- [ ] Extract the candidate archive into a clean location and run the synthetic
  smoke test using only that archive and its declared dependencies.
- [ ] Check required controller paths against
  [check_env.sh](controller/check_env.sh); document that archive checks are not
  a substitute for live site preflight.
- [ ] Generate SHA-256 checksums and release notes covering prerequisites,
  installation, compatibility, known limitations, and validation performed.
- [ ] Generate build provenance attestations and document verification against
  the expected repository and release commit. Keep checksums for download
  integrity; attestations identify the build origin and do not replace review.
- [ ] Tag the exact validated commit and publish the archive and checksums in
  GitHub Releases. Enable immutable releases to prevent replacement of
  published artifacts under an existing release version.
- [ ] Include the existing arXiv paper citation and instructions for identifying
  the exact software release and source commit used in a study.
- [ ] Verify the published download, checksum, and build provenance before
  announcing the release.

**Exit criterion:** users can download a fixed, identifiable release and run
the offline example without cloning the repository.

## 4. Document and validate administrator-managed deployment

This phase requires explicit site approval. It can proceed independently of
the Python packaging work after the first source release.

- [ ] Have the site administrator review the collection protocol, controller
  scripts, dedicated benchmark identity, and Fairshare-reset implications.
- [ ] Verify the release checksum and build provenance, record the archive
  checksum, and install into a fixed versioned directory,
  for example `/opt/wftune/releases/<version>`, visible at the configured path
  from the physical controller and required compute allocations.
- [ ] Make the harness, its direct parent, and protected subtrees root-owned,
  non-group/world-writable, and compliant with existing symlink restrictions.
  Do not use a symlinked harness root. Safe archive modes do not establish the
  permissions of an existing parent directory or external configuration files.
- [ ] Confirm Linux, Bash, Python, Slurm commands, selected workflow manager,
  and treatment-specific dependencies satisfy documented requirements.
- [ ] Copy the appropriate [configuration templates](examples/) outside the
  release tree; set absolute paths and enable only supported treatments.
- [ ] Prepare the workflow-specific semantic validator and frozen input,
  workflow-source, configuration, software, and container manifests.
- [ ] Install the controller environment and validator with the required
  ownership and permissions; verify benchmark-user access where needed.
- [ ] Create separate monitoring, pipeline-output, and lock roots with the
  correct ownership and permissions.
- [ ] Run [preflight](controller/check_env.sh) on the physical controller and
  resolve every failure before collection, including installed-source manifest
  verification.
- [ ] Run an approved pilot campaign, then audit its collected evidence offline.
  Record the site, software versions, treatments tested, and limitations;
  confirm the run records identify the installed release.
- [ ] Document upgrade and rollback: retain old releases, change configured
  paths only between campaigns, rerun preflight, and never silently mix
  software versions within a frozen campaign.

**Exit criterion:** an approved site can install, validate, operate, and roll
back a release using documented steps. Installation itself never resets
Fairshare, submits workloads, or changes Slurm configuration.

## 5. Package the offline analysis CLI

- [ ] Add `pyproject.toml` with a build backend, project metadata, license,
  supported Python versions, dependencies, and console-script entry point.
- [ ] Introduce a proper package namespace, such as `src/wftune/`, and replace
  checkout-dependent imports with package imports.
- [ ] Reuse existing `argparse` parsers and analysis functions; avoid changing
  measurement semantics or adding a CLI framework without a concrete need.
- [ ] Implement the exact [future interface](#future-user-experience), including
  `demo`, `audit`, `summarize`, and the nested `plot walltime-stress` command,
  with the shown positional arguments and `--through-rep` option.
- [ ] Define commands for synthetic examples, audit, summary, plots, cross-WMS
  comparison, and the other supported standalone analysis utilities.
- [ ] Provide `wftune --help`, `wftune --version`, subcommand help, and meaningful
  exit codes. Document any intentionally deferred commands.
- [ ] Preserve existing script entry points through tested compatibility
  wrappers during migration, and keep the complete source bundle usable.
- [ ] Ship the fixtures/resources promised by the CLI and locate them through
  package-resource APIs rather than the caller's working directory.
  If `demo` uses collector code, ship that code as an unprivileged offline
  component so it does not depend on a checkout or controller installation.
- [ ] Keep analysis dependencies out of controller collection. Do not make
  collection import NumPy, pandas, or Matplotlib as a side effect of packaging.
- [ ] Add `src/` (or the chosen package directory) to preflight's protected
  subtrees in the same change that moves analysis code there, even if the
  controller does not import it. Preserve the existing protection of deployed
  analysis code as well as controller code.
- [ ] Declare only tested dependency constraints in package metadata while
  retaining a pinned reference environment for reproducible campaigns.

**Exit criterion:** an installed `wftune` command exposes the documented offline
features without requiring a source checkout or live Slurm access.

## 6. Validate the actual Python distribution artifacts

- [ ] Build both a wheel and source distribution and validate their metadata.
- [ ] Inspect artifact contents for required resources, license notices, and
  accidental inclusion of private or generated files.
- [ ] Install the wheel in a clean environment and run from outside the source
  tree, without an editable installation or repository `PYTHONPATH`.
- [ ] Build/install from the source distribution separately to catch omitted
  source files and build-time dependencies.
- [ ] Exercise the CLI through `pipx` and through `pip` in a virtual environment.
- [ ] Run the exact [future interface](#future-user-experience) sequence against
  the installed artifact, using clean temporary paths. Assert that the default
  demo creates the replicate needed by `--through-rep 1`, the audit succeeds,
  summary tables contain expected values, and the figure is valid and nonempty.
- [ ] Run the same positive and negative synthetic tests against the installed
  CLI, including collector-produced inputs and provenance compatibility cases;
  compare schemas, key values, and failures with the source baseline.
- [ ] Check that the source bundle, Python package, `wftune --version`, run
  provenance, and analysis-output provenance report the expected release
  identities and environments.
- [ ] Test headless plotting, paths containing spaces, and all packaged
  resources needed by supported commands.
- [ ] Verify minimum supported dependency combinations and the pinned reference
  environment across the declared Python/platform matrix.
- [ ] Rebuild and retest the complete controller/source bundle after the package
  refactor so PyPI improvements do not break administrator deployment.

**Exit criterion:** both Python artifacts work in clean environments, preserve
existing analysis behavior, and do not regress the full deployment bundle.

## 7. Publish the analysis package and coordinated release

- [ ] Configure maintainer access and PyPI Trusted Publishing using narrowly
  scoped GitHub Actions permissions and an approval-protected release job.
- [ ] Rehearse publication on TestPyPI; install the exact candidate artifact
  with dependencies resolved from their intended source.
- [ ] Build final artifacts once from the release commit, validate those exact
  artifacts, and promote them only after release approval.
- [ ] Publish the wheel and source distribution to PyPI, and publish the matching
  full deployment bundle, checksums, build provenance, and release notes on
  GitHub. Confirm control of the intended PyPI project after its first upload.
- [ ] Verify installation of the exact published version in a clean environment
  and rerun the offline smoke test before announcing availability.
- [ ] Verify the advertised unversioned `pip install wftune` command from PyPI
  in a clean virtual environment and run the documented future-interface
  sequence, confirming that it resolves to the intended release.
- [ ] Update the [README](README.md) with separate analysis-user and administrator
  installation paths, tested commands, supported environments, and upgrade help.
- [ ] Document that both `pip install wftune` and `pipx install wftune` install
  the offline CLI, not a configured privileged collection service.
- [ ] Document how to report defects and handle a bad release: communicate the
  issue, yank a broken Python version when appropriate, and publish a new fixed
  version instead of overwriting existing artifacts.

**Exit criterion:** published artifacts are verified and both audiences have
clear, accurate installation instructions.

## 8. Maintain reproducibility and add channels only when needed

- [ ] Keep the existing arXiv paper citation and software-version citation
  instructions current; optionally add `CITATION.cff` for machine-readable
  citation metadata.
- [ ] Optionally archive software releases through Zenodo if a software DOI is
  useful. This is not a release requirement. Earlier releases can be uploaded
  manually; keep software-release citations distinct from the paper and data.
- [ ] Keep release notes, compatibility information, and installed-artifact
  smoke tests current for every release, including collection and analysis
  provenance and installed-source verification.
- [ ] Optionally add controller integration tests using the existing
  `WMSbench_*_COMMAND` overrides and fake Slurm commands in an isolated root
  container, without contacting a live cluster.
- [ ] Add Spack or EasyBuild support when an adopting HPC site needs it.
- [ ] Consider a versioned container image for offline analysis if users need
  a frozen environment; do not make it the primary controller installation.
- [ ] Continue distributing only synthetic examples with the software. Review
  real datasets independently before any public release.

## Completion checklist

- [ ] A verified, versioned full deployment bundle is available on GitHub.
- [ ] The analysis CLI installs and runs independently of the repository.
- [ ] Controller deployment remains explicit and administrator-managed.
- [ ] Both artifacts preserve strict evidence validation and data separation.
- [ ] Automated tests cover published-artifact behavior, and any live-site
  validation claims state exactly what was tested.
- [ ] Installation, upgrade, rollback, provenance, and citation are documented.

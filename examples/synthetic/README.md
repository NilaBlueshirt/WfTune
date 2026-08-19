# Synthetic analysis fixture

`make_fixture.py` creates a deterministic, fabricated WfTune monitoring tree
for smoke-testing the audit, summary, and plotting commands without Slurm.

The fixture includes synthetic task traces, lifecycle records, semantic
validation markers, and `sdiag` text for five backends on two fictional cluster
labels. It contains no observations copied from a real campaign. Pass
`--wms snakemake` to generate a second, independently labeled fixture for
smoke-testing the cross-WMS join; this is still parser test data, not a model of
Snakemake performance.

Generate it outside the repository:

```bash
python examples/synthetic/make_fixture.py /tmp/wftune-example --reps 1
```

The generated numbers are intentionally plausible enough to exercise figures,
but they are not evidence and must not be reported, compared, or published as
benchmark results.

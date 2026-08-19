# Energy sampling tools

This directory contains an experimental, standalone energy-measurement layer:

- `rapl_sampler.sh` records node-local powercap energy counters.
- `pdu_sampler.sh` normalizes either a site command or SNMP outlet readings to
  `ts_unix,node,watts` CSV rows.
- `calibrate_rapl_pdu.sh` runs a steady CPU workload while collecting both
  sources so a site can characterize the RAPL-to-whole-node gap.
- `analysis/plot_energy.py` reports calibration and exclusive-run energy.

Use these tools only with the site's approval and on nodes reserved exclusively
for the measurement. PDU access, outlet mapping, and reservation policy are
site-specific. Never commit SNMP communities, credentials, real outlet maps, or
generated energy data.

Calibration example from inside an exclusive one-node allocation:

```bash
export WMSbench_OUT=/path/outside/the/repository/calibration
export WMSbench_PDU_CMD='/absolute/path/to/site-pdu-wrapper --watts --node'
bash energy/calibrate_rapl_pdu.sh

python analysis/plot_energy.py --calib "$WMSbench_OUT"
```

For a backend energy subset, arrange data as
`ROOT/<venue>/energy/<backend>/{rapl,pdu,results}` and run:

```bash
python analysis/plot_energy.py ROOT --venue cluster-a
```

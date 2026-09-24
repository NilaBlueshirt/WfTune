"""The ``wftune`` command for offline analysis of WfTune campaigns.

Each subcommand runs one of the existing analysis tools with that tool's own
options, so ``wftune COMMAND --help`` documents it.  Nothing here contacts
Slurm, needs root, or collects data.
"""
from __future__ import annotations

import importlib
import sys

from . import __version__

COMMANDS = {
    "demo": ("make_fixture", "generate a synthetic monitoring tree to try the tools"),
    "audit": ("audit_campaign", "validate campaign evidence and write the audit report"),
    "summarize": ("summarize_results", "write the per-run, summary, and paired-ratio tables"),
    "trace-resources": (
        "calculate_trace_resources", "compute task resource metrics from Nextflow traces"
    ),
}
PLOTS = {
    "walltime-stress": ("plot_walltime_stress", "walltime against attributable RPC stress"),
    "rpc-accumulation": ("plot_rpc_accumulation", "how RPC stress accumulates over a run"),
    "sdiag-backends": ("plot_sdiag_backends", "cluster context during each backend window"),
    "cross-wms": ("plot_cross_wms", "walltime and RPC count across workflow managers"),
    "single-run": ("plot_single_run", "diagnostic view of one completed run"),
    "energy": ("plot_energy", "per-backend energy from RAPL and PDU samples"),
}


def usage() -> str:
    lines = ["usage: wftune [--version] COMMAND [ARGS...]", "", "commands:"]
    lines += [f"  {name:<17} {text}" for name, (_, text) in COMMANDS.items()]
    lines.append(f"  {'plot FIGURE':<17} draw a figure; FIGURE is one of:")
    lines += [f"    {name:<15} {text}" for name, (_, text) in PLOTS.items()]
    lines += ["", "Run 'wftune COMMAND --help' for that command's options."]
    return "\n".join(lines)


def run(module_name: str, prog: str, args: list[str]) -> int:
    """Run one analysis tool's ``main()`` on ``args``, naming it ``prog``."""
    module = importlib.import_module(f"{__package__}.{module_name}")
    result = module.main(args, prog)
    return 0 if result is None else int(result)


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args:
        print(usage(), file=sys.stderr)
        return 2
    if args[0] in {"-h", "--help"}:
        print(usage())
        return 0
    if args[0] == "--version":
        print(f"wftune {__version__}")
        return 0
    command, rest = args[0], args[1:]
    if command == "plot":
        if not rest or rest[0] in {"-h", "--help"}:
            print(usage(), file=sys.stdout if rest else sys.stderr)
            return 0 if rest else 2
        figure, rest = rest[0], rest[1:]
        if figure not in PLOTS:
            print(f"wftune plot: unknown figure {figure!r}; choose from "
                  f"{', '.join(PLOTS)}", file=sys.stderr)
            return 2
        return run(PLOTS[figure][0], f"wftune plot {figure}", rest)
    if command not in COMMANDS:
        print(f"wftune: unknown command {command!r}\n\n{usage()}", file=sys.stderr)
        return 2
    return run(COMMANDS[command][0], f"wftune {command}", rest)

#!/usr/bin/env bash
# Read the harness release version that every trial records.
#
# The controller runners and both job adapters source this file, so trial.env
# and the in-job pipeline contract apply one rule and the collector can require
# them to agree.  VERSION holds one SemVer 2.0.0 string without build metadata:
# a pre-release tag lets a checkout between releases say so, and build metadata
# has no equivalent in a later Python package version.

WFTUNE_VERSION_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?$'

wftune_read_version() {
    local root=${1:?harness root is required} path content
    path="$root/VERSION"
    [[ -f $path && ! -L $path ]] || {
        echo "harness VERSION is missing, not a regular file, or a symlink: $path" >&2
        return 2
    }
    content=$(<"$path") || return 2
    [[ $content =~ $WFTUNE_VERSION_RE ]] || {
        echo "harness VERSION must be one SemVer line without build metadata: $path" >&2
        return 2
    }
    WFTUNE_VERSION=$content
}

# Warn, without stopping collection, when runs already recorded for a venue
# carry another version.  Analysis rejects such a campaign unless
# --allow-version-drift is given, so the operator hears about it before the
# trial instead of at the audit.
wftune_warn_version_drift() {
    local python=${1:?python is required} venue_dir=${2:?venue directory is required}
    local version=${3:?version is required}
    [[ -d $venue_dir ]] || return 0
    "$python" - "$venue_dir" "$version" <<'PY' || true
import json
import sys
from pathlib import Path

venue_dir, current = Path(sys.argv[1]), sys.argv[2]
others = {}
for path in sorted(venue_dir.glob("rep*/*/run.json")):
    try:
        record = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError):
        continue
    identity = record.get("wftune") if isinstance(record, dict) else None
    version = identity.get("version") if isinstance(identity, dict) else None
    label = version if isinstance(version, str) and version else ""
    if label != current:
        others[label] = others.get(label, 0) + 1
if others:
    detail = ", ".join(
        f"{count} at {label}" if label else f"{count} unrecorded"
        for label, count in sorted(others.items())
    )
    print(
        f"warning: {venue_dir} already holds runs from another WfTune version "
        f"({detail}); this trial records {current}. Analysis rejects a "
        "campaign that mixes versions unless --allow-version-drift is given.",
        file=sys.stderr,
    )
PY
}

"""Shared helper for migration scripts that need a scratch file inside a
remote pod (via kubectl exec). Both generate_hierarchy_relations.py and
user-progress-sync.py needed the identical logic -- extracted here so
there's one copy instead of two (SonarCloud flagged the duplicate as new
code: docker/python duplication gate, new_duplicated_lines_density).

This file is mounted alongside its callers from the same ConfigMap (see
templates/configmap.yaml), at /scripts -- python3 always adds the running
script's own directory to sys.path[0], so `python3 /scripts/foo.py` can
`import remote_temp` with no extra path setup.
"""
import sys

_cache = None


def remote_csv_path(yb_exec):
    """Path of a CSV export file inside the remote pod, created on first use.

    Rather than composing a /tmp path here (python:S5443 -- a hardcoded
    publicly-writable directory, and even a uuid-randomized name is still
    just a guess from the client side), ask the remote pod's own `mktemp`
    to create it: that gets race-free O_EXCL-style creation from the
    system that actually owns /tmp, for free.

    yb_exec: the caller's own kubectl-exec-into-pod helper, so this stays
    agnostic to which pod/namespace each script targets.
    """
    global _cache
    if _cache is None:
        result = yb_exec(["mktemp", "--suffix=.csv"])
        if result.returncode != 0:
            print(f"  FAILED to create remote temp file: {result.stderr.strip()}")
            sys.exit(1)
        _cache = result.stdout.strip()
    return _cache

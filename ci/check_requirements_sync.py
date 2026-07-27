#!/usr/bin/env python3
"""Check the dependency constraints that several files promise to keep in sync.

``requirements.in``, ``.github/workflows/requirements/build-requirements.in``
and ``tables/req_versions.py`` each carry a "keep in sync" comment pointing at
``pyproject.toml``.  Nothing enforced them, so they drifted; this does.

Run as ``python ci/check_requirements_sync.py``.
"""

import sys
import runpy
import tomllib
from pathlib import Path

from packaging.version import Version
from packaging.requirements import Requirement

ROOT = Path(__file__).resolve().parent.parent


def parse_requirements_in(path):
    """Map lowercased name -> Requirement for a pip-compile input file."""
    reqs = {}
    for line in path.read_text().splitlines():
        line = line.split("#")[0].strip()
        if line:
            req = Requirement(line)
            reqs[req.name.lower()] = req
    return reqs


def lower_bound(spec):
    """Return the ``>=`` bound of a specifier set, or None if it has none."""
    for clause in spec:
        if clause.operator == ">=":
            return Version(clause.version)
    return None


def check_specifiers(errors, in_path, pyproject_reqs, pyproject_key):
    """Overlapping names must carry identical specifiers.

    Names present in only one of the two are fine: the ``.in`` files also pin
    tools that are not build/runtime requirements (``pip``, ``build``, ...),
    and ``pyproject.toml`` lists dependencies that CI installs by other means.
    """
    in_reqs = parse_requirements_in(ROOT / in_path)
    for name in sorted(set(in_reqs) & set(pyproject_reqs)):
        got = str(in_reqs[name].specifier)
        want = str(pyproject_reqs[name].specifier)
        if got != want:
            errors.append(
                f"{in_path}: {name}{got or ' (unconstrained)'} does not match "
                f"pyproject.toml {pyproject_key} {name}{want or ' (unconstrained)'}"
            )


def check_req_versions(errors, pyproject_reqs):
    """``req_versions`` minima must match the runtime floors they document."""
    # Executed rather than imported: importing ``tables`` needs the extensions.
    req_versions = runpy.run_path(str(ROOT / "tables" / "req_versions.py"))
    for name in ("numpy", "numexpr"):
        want = lower_bound(pyproject_reqs[name].specifier)
        got = req_versions[f"min_{name}_version"]
        if want is not None and got != want:
            errors.append(
                f"tables/req_versions.py: min_{name}_version = {got} does not "
                f"match pyproject.toml project.dependencies {name} >= {want}"
            )


def main():
    pyproject = tomllib.loads((ROOT / "pyproject.toml").read_text())
    build = {
        Requirement(r).name.lower(): Requirement(r)
        for r in pyproject["build-system"]["requires"]
    }
    runtime = {
        Requirement(r).name.lower(): Requirement(r)
        for r in pyproject["project"]["dependencies"]
    }

    errors = []
    check_specifiers(
        errors,
        ".github/workflows/requirements/build-requirements.in",
        build,
        "build-system.requires",
    )
    check_specifiers(
        errors, "requirements.in", runtime, "project.dependencies"
    )
    check_req_versions(errors, runtime)

    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    if errors:
        print(f"\n{len(errors)} constraint(s) out of sync.", file=sys.stderr)
        return 1
    print("Dependency constraints are in sync.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

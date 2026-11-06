"""Delete paths strictly below OUTPUTS_DIR, .snapshots/ or .envs/; refuse every other path.

Run from the project root: `pixi run python <this dir>/delete.py [--check] <path> [<path> ...]`.
OUTPUTS_DIR and DATA_DIR come from the project's `.env` (python-dotenv, a pydantic-settings dependency).
"""

import argparse
import os
import shutil
import sys
from pathlib import Path

from dotenv import load_dotenv

MARKER = "IN_USE"  # written by a running job, see the slurm-submit skill


def marker_of(target, base):
    """The marker at or above `target` (up to `base`), or anywhere below it."""
    if target.name == MARKER:  # deleting a stale marker itself
        return None
    for directory in [target, *target.parents]:
        if directory == base:
            break
        if (directory / MARKER).is_file():
            return directory / MARKER
    return next(target.rglob(MARKER), None) if target.is_dir() else None


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="report only, delete nothing")
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args()

    assert load_dotenv(".env"), f"no .env in {Path.cwd()}: run from the project root"
    outputs = Path(os.path.expandvars(os.environ.get("OUTPUTS_DIR", ""))).expanduser()
    assert outputs.is_absolute(), f"OUTPUTS_DIR is missing or not absolute: {outputs}"
    repo_roots = [(Path.cwd() / d).resolve() for d in (".snapshots", ".envs")]
    bases = [outputs.resolve(strict=True), *repo_roots]
    data = os.environ.get("DATA_DIR")
    data = Path(os.path.expandvars(data)).expanduser().resolve() if data else None

    for name in args.paths:
        target = Path(name).resolve()  # follows every symlink
        base = next((b for b in bases if b in target.parents), None)  # strictly below a base
        if base is None:
            source = data and (target == data or data in target.parents)
            print(f"refused: {name} -> {target} is not strictly below "
                  + " or ".join(map(str, bases)) + (" (source data, ART-2)" if source else ""))
            continue
        if not target.exists():
            print(f"missing: {target}")
            continue
        marker = marker_of(target, base)
        if marker:
            print(f"in use: {target}, see {marker}")
        elif args.check:
            print(f"ok: {target}")
        else:
            shutil.rmtree(target) if target.is_dir() else target.unlink()
            print(f"deleted: {target}")


if __name__ == "__main__":
    main()

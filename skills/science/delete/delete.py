"""Delete paths strictly below OUTPUTS_DIR or <repo>/.snapshots/; refuse every other path.

Run from the project root: `python3 <this dir>/delete.py [--check] <path> [<path> ...]`.
OUTPUTS_DIR and DATA_DIR come from the project's `.env`, expanded like `Settings` does ($VAR, ~).
"""

import argparse
import os
import shutil
import sys
from pathlib import Path

MARKER = "IN_USE"  # written by a running job, see the slurm-submit skill


def read_env():
    """KEY=value lines of `.env`, keys upper-cased (`Settings` is case-insensitive)."""
    env = {}
    for line in Path(".env").read_text().splitlines():
        line = line.strip()
        if line.startswith("export "):
            line = line[len("export "):]
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            env[key.strip().upper()] = value.strip().strip("'\"")
    return env


def env_path(env, key):
    value = env.get(key)
    return Path(os.path.expandvars(value)).expanduser() if value else None


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

    if not Path(".env").is_file():
        sys.exit(f"delete: no .env in {Path.cwd()}: run from the project root")
    env = read_env()
    outputs = env_path(env, "OUTPUTS_DIR")
    if outputs is None or not outputs.is_absolute():
        sys.exit(f"delete: OUTPUTS_DIR in .env is missing or not absolute: {outputs}")
    bases = [outputs.resolve(strict=True), (Path.cwd() / ".snapshots").resolve()]
    data = env_path(env, "DATA_DIR")
    data = data.resolve() if data else None

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

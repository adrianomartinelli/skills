"""Delete paths strictly below OUTPUTS_DIR or <repo>/.snapshots/; refuse every other path.

Run from the project root: `pixi run python <this dir>/delete.py [--check] <path> [<path> ...]`.
OUTPUTS_DIR comes from the project's `Settings` class (`src/<package>/settings.py`).
"""

import argparse
import importlib
import shutil
import sys
from pathlib import Path

MARKER = "IN_USE"  # written by a running job, see the slurm-submit skill


def load_settings():
    found = sorted(Path("src").glob("*/settings.py"))
    if len(found) != 1:
        sys.exit(f"delete: expected one src/<package>/settings.py below {Path.cwd()}, found {len(found)}")
    sys.path.insert(0, "src")
    return importlib.import_module(f"{found[0].parent.name}.settings").Settings()


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

    settings = load_settings()
    if not settings.outputs_dir.is_absolute():
        sys.exit(f"delete: OUTPUTS_DIR is not absolute: {settings.outputs_dir}")
    bases = [settings.outputs_dir.resolve(strict=True), (Path.cwd() / ".snapshots").resolve()]
    data = getattr(settings, "data_dir", None)
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

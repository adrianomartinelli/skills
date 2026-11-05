---
name: delete
description: Guard for every delete that an agent does. Deletes a path only if it resolves strictly below `OUTPUTS_DIR` or `<repo>/.snapshots/`, and refuses input data, code and every other path. There, clean up and retire obsolete outputs and snapshots as the work needs, without asking the user. Use for every delete in a project with a `Settings` class. Triggers: delete or clean up outputs, runs or snapshots, retire obsolete outputs, free disk space.
---

# delete

`AGENTS.md` ART-6 sends every delete that an agent does to this skill. Everything below
`OUTPUTS_DIR` and `<repo>/.snapshots/` is reproducible: the code writes the outputs again, and
`create_snapshot.sh` builds a snapshot again from its commit. Delete obsolete paths there as the
work needs. Every other path stays: input data under `DATA_DIR`, code, `.logs/`. Ask the user to
delete such a path.

From the project root, run this script with `<project_name>` filled in and the paths as arguments.
A list or a glob is fine.

```
pixi run python - <path> [<path> ...] <<'EOF'
import shutil
import sys
from pathlib import Path

from <project_name>.settings import Settings

MARKER = "IN_USE"  # written by a running job, see the slurm-submit skill
settings = Settings()
assert settings.outputs_dir.is_absolute(), f"OUTPUTS_DIR is not absolute: {settings.outputs_dir}"
bases = [settings.outputs_dir.resolve(strict=True), (Path.cwd() / ".snapshots").resolve()]
data = getattr(settings, "data_dir", None)
data = data.resolve() if data else None


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


for name in sys.argv[1:]:
    target = Path(name).resolve()  # follows every symlink
    base = next((b for b in bases if b in target.parents), None)  # strictly below a base
    if base is None:
        source = data and (target == data or data in target.parents)
        print(f"refused: {name} -> {target} is not strictly below {' or '.join(map(str, bases))}"
              + (" (source data, ART-2)" if source else ""))
    elif not target.exists():
        print(f"missing: {target}")
    elif marker := marker_of(target, base):
        print(f"in use: {target}, see {marker}")
    else:
        shutil.rmtree(target) if target.is_dir() else target.unlink()
        print(f"deleted: {target}")
EOF
```

- If `Settings()` raises, stop and show the user the error. `Settings` refuses a missing or
  relative `OUTPUTS_DIR`.
- Tell the user each `refused` line. Do not delete a refused path in a different way.
- An `in use` line names the marker of a running job. The marker holds the job ID. If
  `sacct -j <job_id> -X -n -o State` shows that the job ended, the marker is stale: delete the
  marker with this script, then the path.

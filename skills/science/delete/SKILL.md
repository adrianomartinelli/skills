---
name: delete
description: Guard for every delete that an agent does. Deletes a path only if it resolves strictly below `OUTPUTS_DIR`, and refuses input data, code and every other path. Below `OUTPUTS_DIR`, clean up and retire obsolete outputs as the work needs, without asking the user. Use for every delete in a project with a `Settings` class. Triggers: delete or clean up outputs or runs, retire obsolete outputs, free disk space.
---

# delete

`AGENTS.md` ART-6 sends every delete that an agent does to this skill. Everything below
`OUTPUTS_DIR` is an artifact of the project's code, and the code can write it again. Delete obsolete
outputs there as the work needs. Every other path stays: input data, code, `.snapshots/`, `.logs/`,
and paths outside `OUTPUTS_DIR` that the code writes (for example `data/processed/`). Ask the user
to delete such a path.

## Delete

1. If Slurm is on the machine, run `squeue --me -h -t RUNNING,PENDING -o '%i %j %Z'`. Leave out
   each path that a listed job writes to.
2. From the project root, run this script with `<project_name>` filled in and the paths as
   arguments. A list or a glob is fine.

```
pixi run python - <path> [<path> ...] <<'EOF'
import shutil
import sys
from pathlib import Path

from <project_name>.settings import Settings

settings = Settings()
assert settings.outputs_dir.is_absolute(), f"OUTPUTS_DIR is not absolute: {settings.outputs_dir}"
root = settings.outputs_dir.resolve(strict=True)
data = getattr(settings, "data_dir", None)
data = data.resolve() if data else None
for name in sys.argv[1:]:
    target = Path(name).resolve()  # follows every symlink
    if root not in target.parents:  # also refuses OUTPUTS_DIR itself
        source = data and (target == data or data in target.parents)
        print(f"refused: {name} -> {target} is not strictly below {root}"
              + (" (source data, ART-2)" if source else ""))
    elif target.is_dir():
        shutil.rmtree(target)
        print(f"deleted: {target}")
    elif target.exists():
        target.unlink()
        print(f"deleted: {target}")
    else:
        print(f"missing: {target}")
EOF
```

If `Settings()` raises, stop and show the user the error. `Settings` refuses a missing or relative
`OUTPUTS_DIR`.

Tell the user each `refused` line. Do not delete a refused path in a different way.

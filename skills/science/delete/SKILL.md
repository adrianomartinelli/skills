---
name: delete
description: Delete one artifact path below `OUTPUTS_DIR` (a run, a checkpoint, a figure set) with the checks of `AGENTS.md` ART-1, ART-2 and ART-6. Use before any delete in a project with a `Settings` class. Triggers: delete or clean up runs or outputs, free disk space.
---

# delete

Everything below `OUTPUTS_DIR` is an artifact of the project's code: run identity keeps runs
apart, and the code can write a deleted artifact again. Every other path stays: source data, the
rest of the output tree (for example `data/processed/`), the code, `.snapshots/`, `.logs/`. Ask
the user to delete such a path.

> [!CAUTION]
> **One path for each delete.** The user names the path, you check it, the user approves it, you
> delete it. Run the steps again for the next path. A loop, a glob or a rule selects paths that
> nobody looked at. A sweep over "has `config.json`, lacks `summary.json`" once moved the output
> of a running job away and stopped the job.

Stop at the first step that fails, and tell the user which check failed and why.

## Step 1: Get the named path

Use the path exactly as the user wrote it in their message. A path that you found yourself is not
named, for example from a listing, a glob, a run name or "the old runs". Show it to the user and
ask them to name it. A relative path resolves against the project root.

Done when you have one path, in the user's own words.

## Step 2: Check the path against `OUTPUTS_DIR`

Get `OUTPUTS_DIR` from the project's `Settings` class, not from the shell environment (CFG-2).
From the project root, run this, with `<project_name>` and `<named path>` filled in:

```
pixi run python - <<'EOF'
from pathlib import Path
from <project_name>.settings import Settings

outputs = Settings().outputs_dir
assert outputs.is_absolute(), f"OUTPUTS_DIR is not absolute: {outputs}"
root = outputs.resolve(strict=True)
target = Path("<named path>").resolve(strict=True)
assert root in target.parents, f"{target} is not strictly below {root}"
print(target)
EOF
```

The script follows every symlink, in `OUTPUTS_DIR` and in the target. A target that is a symlink to
a path outside `OUTPUTS_DIR` fails. `OUTPUTS_DIR` itself fails: it is not strictly below itself.

- **`OUTPUTS_DIR` is not absolute.** `Settings.outputs_dir` defaults to the relative `outputs`, and
  a relative root resolves against the working directory (in a snapshot, inside the snapshot). Ask
  the user to set `OUTPUTS_DIR` to an absolute path in `.env`.
- **The path is not strictly below `OUTPUTS_DIR`**, or does not exist. Do not delete it. If it is
  under `DATA_DIR`, it is source data (ART-2).

Done when the script prints one resolved path. Use this resolved path in every later step.

## Step 3: Ask the scheduler

A job can write to a directory with no sign of it in the directory. Get liveness from the
scheduler only:

```
squeue --me -h -t RUNNING,PENDING -o '%i %j %Z'
scontrol show job <job-id>
```

For each running or pending job, look at its working directory, its command, its `StdOut` and
`StdErr`, and the run identity in its name or config. If a job can write to the resolved path or
below it, stop and tell the user which job. If you cannot tell, ask the user. If `squeue` is not on
the machine, ask the user whether a run writes to the path.

Done when no running or pending job writes to the path.

## Step 4: Get an explicit yes

Show the user the resolved path and its size (`du -sh <resolved path>`), and ask whether to delete
it. Only a clear yes to this path, in this turn, approves it. An approval of an earlier path, or of
"the old runs", does not.

Done when the user answered yes to this one path.

## Step 5: Delete exactly that path

```
rm -r -- <resolved path>
test ! -e <resolved path> && echo deleted
```

Done when the command prints `deleted`. Tell the user the path that you deleted and its size.

---
name: delete
description: Guard for every delete that an agent does. Deletes a path only if it resolves strictly below `OUTPUTS_DIR` or `<repo>/.snapshots/`, and refuses input data, code and every other path. There, clean up and retire obsolete outputs and snapshots as the work needs, without asking the user. Use for every delete in a project with `OUTPUTS_DIR` in `.env`. Triggers: delete or clean up outputs, runs or snapshots, retire obsolete outputs, free disk space.
---

# delete

`AGENTS.md` ART-6 sends every delete that an agent does to this skill. Everything below
`OUTPUTS_DIR` and `<repo>/.snapshots/` is reproducible: the code writes the outputs again, and
`create_snapshot.sh` builds a snapshot again from its commit. Delete obsolete paths there as the
work needs. Every other path stays: input data under `DATA_DIR`, code, `.logs/`. Ask the user to
delete such a path.

From the project root, run:

```
pixi run python <this skill's base directory>/delete.py [--check] <path> [<path> ...]
```

A list or a glob is fine. `--check` reports each path and deletes nothing. The script reads
`OUTPUTS_DIR` from the project's `.env`, follows every symlink, and deletes a path only if
it is strictly below `OUTPUTS_DIR` or `.snapshots/` and carries no `IN_USE` marker.

- If an assert fails (no `.env`, or a missing or relative `OUTPUTS_DIR`), show the user the error.
- Tell the user each `refused` line. Do not delete a refused path in a different way.
- An `in use` line names the marker of a running job. The marker holds the job ID. If
  `sacct -j <job_id> -X -n -o State` shows that the job ended, the marker is stale: delete the
  marker with `delete.py`, then the path.

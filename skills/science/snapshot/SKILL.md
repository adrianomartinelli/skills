---
name: snapshot
description: Freeze one commit of a repository (its files, its own pixi environment, its `.env`) in `<repo>/.snapshots/<commit>/` with `create_snapshot.sh`, and run Slurm jobs and pinned agent sessions from it instead of the live checkout. Covers why (parallel work, queued jobs, no installs at run time), the layout and logs, and how to start a job or a session in a snapshot. Use before submitting a Slurm job, before launching an agent session that must stay on one commit, or when several agents or humans work in one repository at once. Triggers: "snapshot", "create_snapshot", "freeze the code", "run from a snapshot", "launch an agent in a snapshot".
---

# snapshot

A snapshot is one commit of the repository with its own environment, at
`<repo>/.snapshots/<commit>/`. Slurm jobs and pinned sessions run from it, never from the live
checkout. `slurm-submit` (jobs) and `agentic-system-design` (agent sessions) build on this skill.

> [!CAUTION]
> **Never point a job or a pinned session at the live checkout.** The code under it changes with
> every commit that lands there, and nothing reports it.

## Why snapshots exist

1. **Parallel work.** Agents and humans keep committing to the checkout while others work. A
   session that runs from the snapshot of its commit keeps that code to the end, and everyone else
   keeps working on the codebase. A workflow agent always runs in the snapshot of the commit it was
   set up at.
2. **Queued jobs.** A Slurm job reads the code when it *starts*, not when it is submitted, and it
   can start hours later. From a snapshot, it runs the code it was submitted against.
3. **No installs at run time.** Every `pixi run` in a snapshot is
   `pixi run --frozen --no-install`, with both flags written out. `--frozen` stops pixi from
   resolving the lock again, and `--no-install` stops it from touching the environment. Without
   them, jobs that start together in one snapshot install into the same environment at the same
   time (a race), and a compute node without network fails the install.

## Create one

From the live checkout:

```
bash <this skill's base directory>/create_snapshot.sh --log <name>
```

The last line of stdout is the snapshot's path. Paste that path literally into the next command.

- `--commit <sha>`: the commit to freeze. The default is `HEAD`, and then the script refuses
  uncommitted changes to tracked files: they would look included and are not. Untracked files do
  not count.
- `--log <name>`, repeatable: makes `.logs/<commit>/<name>/` for job output. `<name>` is one path
  segment: the script, skill or agent that submits.

Call it before every submission: a finished snapshot is reused, and only the log folders are added.
One snapshot per commit, shared by every session and job of that commit.

**Where the script is.** Claude Code prints the skill's base directory when the skill loads. A
project that calls the script from its own code, an allowlist or an `--allowedTools` entry needs a
fixed path: it vendors this skill to `.claude/skills/snapshot/` and calls
`bash .claude/skills/snapshot/create_snapshot.sh`. A project with an admin CLI wraps the script in
its own `create_snapshot` command. It does not implement the steps again.

What the script does. Each step prevents a failure seen in practice:

1. **`git archive` of the commit, not `git worktree`.** The snapshot is a plain folder without
   `.git`, so no git command can switch its code, and nothing breaks when the checkout moves.
2. **One environment per snapshot**, installed from the commit's own lock with
   `pixi install --all --locked`. Nothing outside the snapshot can change it. `--all` installs every
   environment, because a job can run `pixi run -e <env>` and a compute node cannot install one.
   pixi hardlinks packages from its cache, so each environment costs little disk as long as the
   cache is on the same filesystem as the repository.
3. **`.env` is copied, not linked.** A later edit must not change the settings of a running job.
   A relative path in it (a `*_DIR`, `*_PATH` or `*_ROOT` key) is refused: from a snapshot it
   resolves inside the snapshot, and fails as "no data", not as an error. The script sees only the
   keys written in `.env`, not a relative default that `.env` never sets. A project with a settings
   class makes every path setting required and absolute in that class, so loading the settings
   refuses what the script cannot see.
4. **`snapshot.yaml` is written last** (commit, lock hash, time). A snapshot without it is not
   finished, and the next call finishes it.

**An editable dependency outside the repository** (`path = "../sibling"`) resolves against the
snapshot's folder, where it does not exist. The script links it to its real place. pixi's lock
check rejects that link, so such a project installs with `--frozen` instead of `--locked`. Keep the
lock current in the checkout (`pixi install --locked` there), because nothing checks it in the
snapshot.

## Layout and logs

```
<repo>/
  .snapshots/<commit>/                      # files, .pixi/, .env, snapshot.yaml
    .logs -> <repo>/.logs/<commit>/
  .logs/<commit>/
    snapshot.log                            # what create_snapshot did
    <name>/<job-id>-<job-name>.{out,err}    # one pair per Slurm job, for inspection
```

Add `.snapshots/` and `.logs/` to `.gitignore`.

- **Snapshots stay inside the repository.** Claude Code runs a session's hooks only in a trusted
  folder, and a folder inside a trusted one counts. A snapshot elsewhere runs its sessions with
  their hooks skipped, with no error.
- **Logs stay in the checkout, not in the snapshot.** A snapshot can be deleted once its jobs end
  (check with `squeue`), and that must not delete the record of what its jobs did.

## Run from one

**A Slurm job.** Run the job in the snapshot with literal paths, and pin its logs:

```
sbatch --chdir=<snapshot> --job-name=<job> --output=<repo>/.logs/<commit>/<name>/%j-%x.out --error=<repo>/.logs/<commit>/<name>/%j-%x.err ... --wrap="pixi run --frozen --no-install <command>"
```

A job submitted from inside a snapshot (a pinned session's own job) runs in that snapshot. It does
not need a new one.

**A session (an agent).** Start it as its own process with the snapshot as its working directory.
Claude Code sets `CLAUDE_PROJECT_DIR` to that folder at start-up, and hooks run from
`CLAUDE_PROJECT_DIR`. So the session's hooks run the snapshot's code too. Never start a pinned
role as a subagent of the Agent tool: a subagent runs in the working directory of its parent, the
live checkout, so it runs unpinned code under the parent's hooks. `agentic-system-design` covers
`launch`, the binding of a session to an agent, and the agent's own call log.

**Git inside a snapshot.** A snapshot has no `.git`, so git walks up to the live checkout:
`git rev-parse HEAD` there reports the checkout's commit, not the snapshot's, and `git checkout`
changes the checkout. Code that needs its own commit reads the snapshot's folder name or
`snapshot.yaml`. For the same reason, run `create_snapshot.sh` from the checkout; it refuses to run
inside a snapshot.

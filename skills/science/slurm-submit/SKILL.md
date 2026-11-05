---
name: slurm-submit
description: Job submission workflow for this cluster -- commit/snapshot/canary/fan-out sequence (canary only when jobs share a submission mechanism, e.g. a fold/seed sweep -- a single independent run skips it), fast_dev_run as a Lightning training job's own pre-submission check, immutable code and environment snapshots, and account/fair-share mediation when jobs won't start. Archiving what a job produced is the artifacts skill. Builds on the slurm-ops skill (right-sizing, diagnostics). Use for sbatch, srun, job arrays, sweeps, "submit a job", "run on the cluster".
---

# slurm-submit

Owns *how a job actually gets submitted and run*, as distinct from `slurm-ops` (how big it should
be, and how to triage it once it's in the queue). Read `slurm-ops` first if you haven't sized the
job yet -- this skill assumes you already have a canary-measured `--time`/`--mem`/`--cpus`.

## Don't check in a resource-spec wrapper

A `.sbatch` file that is only `#SBATCH` directives plus a one-line CLI call to an already-typed,
already-parameterized entrypoint should not be a checked-in file. Every partition rename, QOS fix,
or step-count tweak to that file is a commit, and a commit is a new snapshot -- paying the whole
commit -> snapshot -> canary sequence for a change that touched no code at all. (Seen directly: a
project's array script hard-coded a partition/QOS pair that no longer existed on the cluster; the
fix was a `--partition`/`--qos` override on the `sbatch` command line, not a file edit, precisely
because nothing forced those values to live in a versioned file in the first place.)

Prefer `sbatch --wrap='<command>'` (or a heredoc for a multi-line command), with the directives
passed as `sbatch` flags and the command documented in a project doc (e.g. `docs/slurm-runs.md`)
rather than encoded in a tracked script. Changing a value is then editing the command you paste at
submit time, not editing and re-snapshotting a file.

The exception is a fan-out mechanism whose *logic* is the artifact -- a lookup table an array index
resolves into a row/config, especially one covered by a test. That is real code, not a resource
spec, and the canary rule below already says a real fan-out mechanism must not be replaced by a
hand-equivalent stand-in -- which cuts the other way too: keep it a checked-in, tested file rather
than folding it into a `--wrap` string that nothing can typecheck or lint.

## QOS/account/partition inventory: check the project doc first

- Before choosing `--qos`/`--account`/`--partition`, check the project's `docs/hpc.md` for a
  persistent inventory of what exists on this cluster, which account(s)/QOS combos are usable,
  and quirks that aren't discoverable from a single `sinfo`/`sacctmgr` call (e.g. a QOS that
  silently rejects submissions outside some parameter range).
- If `docs/hpc.md` doesn't exist yet, don't guess: run `sacctmgr show assoc user=$USER
  format=account,qos%40 -p`, `sinfo -o "%P %l %G"`, and `scontrol show partition` to discover
  what's actually usable, then write the findings to `docs/hpc.md` (an account/QOS/partition
  table plus a running "quirks" list) before submitting, so the next session or agent doesn't
  redo the same exploration.
- Treat `docs/hpc.md` as living: when a submission fails for a QOS/partition/account reason not
  yet recorded there, add a one-line note once it's resolved.

## Commit -> snapshot -> canary -> fan-out sequence

> [!CAUTION]
> **Never point a job at the live checkout.** A queued job reads the working tree when it *starts*,
> not when it was submitted, so commits that land during the queue wait silently change what it
> runs. Steps 1 and 2 below are the fix.

Combines `slurm-ops`'s "canary before fan-out" with the project-level snapshot policy
(`AGENTS.md`, RUN-11) into one recipe -- neither states it as a single sequence
on its own, so it's spelled out here:

1. **Commit** whatever the job will run. A working tree that keeps changing under a multi-hour
   fan-out is exactly what the snapshot step exists to prevent.
2. **Snapshot** that commit with `snapshot.sh <name>`, which prints the snapshot path. `<name>` is
   the script or skill submitting the job and groups its logs:

   ```bash
   snapshot=$(bash .claude/skills/slurm-submit/snapshot.sh <name>)
   sbatch --chdir="$snapshot" \
     --output="$snapshot/.logs/<name>/%j-%x.out" --error="$snapshot/.logs/<name>/%j-%x.err" ...
   ```

   It does five things, and each corresponds to a failure seen in practice:

   - **Logs in the live checkout, not the snapshot.** `.logs/<name>/<job-id>-<job-name>.{out,err}`
     (and `.log` for a log file the job writes itself, e.g.
     `$SLURM_JOB_ID-$SLURM_JOB_NAME.log`) sit under the repository root; the snapshot only holds a
     `.logs` symlink to it. Logs written into the snapshot itself made every snapshot
     undeletable, because removing it removed the only record of its jobs. `--output` is an
     sbatch argument, so nothing in the project's settings or path classes governs it -- this is
     the one place that does. `snapshot.sh` also creates `.logs/<name>/` up front: Slurm does not
     create a missing output directory, and a job that cannot open its log fails without writing
     one.

   - **`git archive`, not `git worktree`.** An archive is a plain directory with no `.git`, so
     nothing can `checkout` inside it, there is no worktree bookkeeping to leak, and it cannot
     break if the main repo is moved or garbage-collected. A worktree is a *mutable checkout*
     that git tracks -- weaker for something whose only job is to stay identical.
   - **Refuses a dirty tree.** An archive extracts a commit, so uncommitted work is simply absent.
     Submitting from a dirty tree means running something nobody reviewed, silently.
   - **Environments addressed by `sha256(pixi.lock)`**, at `<repo_root>/.envs/<repo>-<hash>/` by
     default (override with `ENV_ROOT`; `$HOME` is a poor default since home directories commonly
     carry a small quota on shared clusters), symlinked
     into the snapshot. This is the subtle one: sharing a live `.pixi` means a `pixi install` in
     the working tree mutates the environment *under a running job* -- the exact class of failure
     the snapshot exists to prevent -- while building a private environment per snapshot wastes
     GBs re-resolving an identical lock. Hashing the lock gets both: same lock means the same
     immutable environment, safely shared; changed dependencies mean a new hash and a new
     directory, so running jobs keep theirs.
   - **Rejects relative paths in `.env`.** A relative path resolves against the process's working
     directory; from a snapshot that is a fresh empty directory *inside the snapshot*, not the
     real dataset -- and it fails silently, as "no data" rather than as an error.

   `.env` is copied rather than symlinked, for the same reason the environment is not shared: a
   symlink would let a later edit change a running job's configuration.

   **An editable pypi-dependency that lives outside the repo breaks under this.** A relative
   `path = "../sibling-repo"` editable dependency in `[tool.pixi.pypi-dependencies]` resolves
   against the directory containing `pyproject.toml` -- the live repo root during normal
   development, but the *snapshot's* root once jobs run from `git archive`, which sits at a
   completely different filesystem depth (`<repo_root>/.snapshots/<repo>/<sha>` by default, not next to the sibling
   repo). `../sibling-repo` from there resolves to something that doesn't exist. Two fixes that
   look plausible and don't work: symlinking the target into place under the snapshot (pixi's
   freshness check compares path identity in a way a symlink doesn't satisfy, even though it
   resolves to the right place) and rewriting the path to absolute in the snapshot's
   `pyproject.toml` (`pixi.lock` carries its own relative record of the same path and gets
   re-resolved from the snapshot's location regardless of what the manifest says). The actual fix
   is two-part: run `pixi install --locked` in the *live* repo root, where the relative path is
   genuinely valid, as the freshness check (this is what `snapshot.sh` does); then build the
   snapshot's own environment with `--frozen` instead of `--locked` -- `--frozen` installs exactly
   what's pinned without re-deriving freshness at all, so the location mismatch never gets a
   chance to produce a false failure. It still has to physically open the dependency's source to
   install it, which is why `snapshot.sh` also recreates each such editable dependency as a symlink
   inside the snapshot pointing at its real location: a symlink is fine for a plain file open, only
   pixi's freshness comparison rejected it.
3. **Canary only when jobs will share one submission mechanism -- not by default.** A canary exists
   to catch a bug that would otherwise break *every* job in a batch the same way (a bad path, a
   broken per-task lookup, a wrong flag copy-pasted N times). A single independent training run --
   its own data, its own model, one job -- has no such shared mechanism to protect: there is
   nothing to fan out, so submit it directly and skip the canary step entirely.

   The case that *does* need one: several jobs that are the same training/model varying only a
   parameter such as fold or seed. Default to **plain terminal `sbatch --wrap='...'` per job**,
   not a Slurm array with a `.sbatch` file and an index-lookup table to maintain -- for an
   enumerable sweep (a handful of folds/seeds), one `--wrap` invocation per job is less to get
   wrong and nothing to keep in sync with a separate script. In that shape, the "canary" is simply
   **the first real job**, submitted exactly the way the rest will be:

   ```bash
   sbatch --account=<acct> --partition=<p> --qos=<p>-<tier> --gres=gpu:1 --time=<h>:00:00 \
     --chdir="$snapshot" --job-name=fold-0 \
     --output="$snapshot/.logs/train/%j-%x.out" --error="$snapshot/.logs/train/%j-%x.err" \
     --wrap="PYTHONPATH=$snapshot/src pixi run --frozen --no-install python <entry point> --fold=0 ..."
   ```

   **`--frozen --no-install` is not optional.** Plain `pixi run` first brings the environment up to
   date. Environments are shared by lockfile hash across snapshots (see `snapshot.sh`), and the
   project is installed into them as an editable pypi dependency whose recorded path is whichever
   tree last synced that env. Run from a *different* snapshot, pixi tries to re-link that editable
   install — and when the tree it points at is gone, every job in the batch dies within seconds:

   ```
   × Failed to update PyPI packages for environment '<env>'
   ╰─▶ failed to remove directory `.../site-packages/<pkg>-<ver>.dist-info`: No such file or
       directory (os error 2)
   ```

   `--no-install` stops pixi touching the environment at all; `--frozen` stops it re-resolving the
   lock. `PYTHONPATH` is still needed alongside them, for the separate reason `snapshot.sh` gives:
   it decides which snapshot's *source* is imported, which the editable install would otherwise
   decide for you.

   If it's green, its output is a **kept datapoint**, not a throwaway probe -- there is no separate
   canary-only output tree for this case, because the run and the canary are the same job. Submit
   the remaining folds/seeds only once that first job's real artifact exists and looks right
   (`summary.json`, not just job state). This is different from `fast_dev_run` below: `fast_dev_run`
   checks the code runs at all, in seconds, before *any* real job; this per-sweep canary checks the
   first real job of a batch before committing to the rest, and its result counts.

   **If a sweep is large enough that an array genuinely is the right tool** (dozens-plus jobs,
   input selected by `$SLURM_ARRAY_TASK_ID`), canary through the *exact* fan-out mechanism, not a
   hand-equivalent stand-in -- a one-task array job doing the same lookup, not a single
   `sbatch --wrap=...` with the value filled in directly. A hand-crafted canary can pass while the
   actual array-lookup plumbing is broken. Concretely bit us once: `mktemp` put a job's input list
   in `/tmp`, which is local to the *login* node and invisible to compute nodes -- a hand-invoked
   canary looked fine, and every task in a real 4407-task fan-out then exited 0 having silently
   done zero work, because each task's list lookup failed and got treated as "nothing to do"
   instead of an error. Fixed two ways: put shared-input files under the snapshot directory (real
   shared storage), and make the per-task lookup fail loudly (non-empty check, `exit 1`) instead of
   degrading into a silent no-op. If that canary is green (real output, not just exit code 0), fan
   out the full array from the same snapshot.
4. **Verify a finished sweep or fan-out**, not just its job states. `sacct` exit codes and
   "COMPLETED" only prove nothing crashed; check that the expected artifact count actually grew
   (e.g. count output files before and after, not just before submitting and after everything
   reports done).

This canary/fan-out discipline is not training-specific -- it applies to any batch of jobs sharing
a submission mechanism (data processing, promotion, conversion). `fast_dev_run` below is narrower:
a Lightning-specific pre-submission check for one training job, canary or not.

## `fast_dev_run`: a Lightning training job's own pre-submission check

Before submitting *any* Lightning training job -- canary, sweep member, or one-off -- run it with
`Trainer(fast_dev_run=True)` (wire it through the project's own config/CLI if it isn't already)
via `srun` on a short interactive/CPU allocation, never on the login node. It runs one training
(and one validation)
batch end to end -- construction, forward, backward, optimizer step -- so a broken config, a shape
mismatch, or a wiring bug surfaces in seconds instead of after a real submission queues and starts.

**It does not touch the run's own `max_steps`/config -- do not shrink `max_steps` to "make it
fast".** `fast_dev_run` only caps Lightning's *own* loop to one batch; any code that validates
schedule shape against `max_steps` at construction time (a warmup assert, a cosine horizon) still
builds against the real value, before `fast_dev_run` gets a chance to limit anything. Shrinking
`max_steps` below that value re-triggers exactly the assert it's meant to protect against (seen
directly: `max_steps must exceed warmup_steps`, only fixed by leaving `max_steps` at its real,
un-shrunk value and letting `fast_dev_run`'s internal cap supply the speed). The dev run should be
the exact real invocation plus one added flag, never a hand-edited config.

**Check what else `fast_dev_run` does *not* cover.** It caps the fit loop only -- any downstream
step that walks a full dataset by hand (feature extraction for a probe, an end-of-run evaluation
pass, a heavy post-training GPU step) runs at full size regardless, silently defeating the point of
a "fast" dev run. If a training script has such a step, gate it explicitly behind the same flag
(`if config.fast_dev_run: return` before it) -- a 1-batch fit has nothing meaningful for a full
evaluation to measure anyway.

**Always route `fast_dev_run` output to a scratch location, not the real output tree**, by default,
not as a step to remember. A dev run's config is usually identical to the real job it is checking,
so writing under the real output root would claim that run's identity and, under a no-overwrite
artifact guard, permanently block the real job's own first write. The robust way to get this is to
key the redirect off the flag itself in code (e.g. `outputs_dir = tempdir() if fast_dev_run else
real_outputs_dir`) rather than an environment variable the caller has to remember to set --
`fast_dev_run` should be safe to reach for blindly, with no separate output-isolation step.

## Requeue is on by default, and a framework's auto-requeue does not cover the case that matters

`JobRequeue=1` is the usual `slurm.conf` default, so *every* job is requeueable unless submitted
with `--no-requeue`. Check it rather than assume: `scontrol show job <id> | grep -o "Requeue=[0-9]*
Restarts=[0-9]*"`. A requeue re-runs the batch script **from the top** -- it is not a resume, and it
fires on node failure and preemption (not on walltime expiry, which is a plain kill, and not on
`scancel`).

So every job needs its own answer to "what happens when my script runs again from line 1". The
failure is silent when the script's answer is "start over", because nothing errors: the job is
`RUNNING` again, the GPU is busy again, and the artifact directory fills up again.

**Do not assume the training framework handles it.** Lightning prints `SLURM auto-requeueing
enabled. Setting signal handlers.` whenever it detects SLURM, which reads like the problem is
solved. It is not: `SLURMEnvironment.auto_requeue` only covers the **signalled** path -- on
`SIGUSR1` it writes an `hpc_ckpt_*.ckpt` and calls `scontrol requeue`, and the checkpoint connector
auto-detects that file on restart. A hard node failure sends no signal, so there is no hpc
checkpoint, and `trainer.fit(..., ckpt_path=None)` then trains from scratch under the same output
directory. Seen directly on this cluster: six GPU jobs all carrying `Requeue=1`, of which the
framework-managed half would have restarted at step 0.

The fix is one argument -- `ckpt_path=args.resume_from or "last"`, keeping an explicit
`--resume-from` authoritative. `"last"` is safe before the first checkpoint exists: Lightning warns
and loads nothing rather than raising (`checkpoint_connector.py`, *"not an error so it can be set
and forget before the first `fit` run"*). Check the equivalent for any other framework: detectron2
/ fvcore's `checkpointer.resume_or_load(..., resume=True)` reads `last_checkpoint`, and a bare
`sbatch --wrap` around a plain script has no answer at all until one is written.

**Then check what a restart does to the artifacts**, which is the part that outlives the lost
compute. A metrics file opened in append mode (`open("a")`) will interleave the restarted run's
rows with the original's in one file -- no error, no lost bytes, and every downstream consumer
plots two trajectories as one curve. A non-monotonic step/iteration column is the tell; a writer
that refuses to write over an existing artifact (see the `artifacts` skill) is the cure.

## A CLI-override trap that bites exactly this kind of fan-out

A sweep submitted as several invocations with per-job CLI overrides can silently run the wrong
config if a varying value sits inside a union field. See the union rule in the `jsonargparse`
skill's "Invoking an endpoint" section before writing the per-job commands.

## Preflight: prove the job shape can land before choosing a partition

Do this *before* submitting, not by reading a pending reason afterwards. Four failure modes, each
of which silently wasted a night's scheduling:

**1. Free GPUs are not a schedulable slot.** `sinfo -p <part> -O Gres,GresUsed` can show six of
eight GPUs free while every node is `allocated` on CPU or memory, so an 8-CPU / 64 GB job can never
land. Check all three dimensions together:

```bash
sinfo -p <part> -h -O "NodeList:16,Gres:22,GresUsed:22,CPUsState:18,FreeMem:10,StateLong:12"
```

`CPUsState` is `allocated/idle/other/total` -- the second field is what a new job can take. A node
with free GPUs and `0` idle CPUs is full.

**2. A far-future `START_TIME` means "never", not "later".** After submitting, check:

```bash
squeue -j <id> -o "%.12i %.9T %.20r %.20S"
```

A start estimate years away (seen: 2027) is the scheduler saying the request cannot be satisfied on
that partition. Treat it as an abort signal and resubmit elsewhere rather than waiting.

**3. QOS acceptance is not QOS permission.** `sbatch` will happily accept `--qos=1day` and the
partition will then refuse it, leaving the job pending forever with
`Job's QOS not permitted to use this partition`. Submission succeeding proves nothing. QOS names
are usually per-hardware (`l40s-1day`, `h200-6hours`), so a multi-partition list needs a QOS every
listed partition allows. Enumerate before submitting:

```bash
scontrol show partition <part> | grep -o "AllowQos=[^ ]*"
```

Tiers are typically `30min / 6hours / 1day / 1week` -- there is no 8h or 12h tier, so anything over
six hours uses the `1day` tier. A QOS permitted everywhere may exist but be a privileged allocation
(higher priority, much longer wall); treat using one as an entitlement decision for the user, like
choosing an account to charge.

**4. Never infer device sharing from `CUDA_VISIBLE_DEVICES`.** Under cgroups every job sees its own
GPU renumbered to `0`, so `CUDA_VISIBLE_DEVICES=0` in every task looks like device sharing and is
not. To settle it, submit two short jobs printing both variables:

```bash
sbatch ... --wrap='echo "host=$(hostname) CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES SLURM_JOB_GPUS=$SLURM_JOB_GPUS"'
```

Two jobs on the same host with **different `SLURM_JOB_GPUS`** are isolated, whatever
`CUDA_VISIBLE_DEVICES` says. Getting this wrong in the pessimistic direction is expensive but
invisible: a belief that `--gres=gpu:1` does not isolate forced `%1` serialisation on every array
job, turning parallel work into sequential work for months. A shared-resource claim is cheap to
test and should never be carried on assumption.

**Sizing from a canary.** A run's reported `wall_seconds` typically covers only the fit loop, not
data setup, probing or checkpoint writes, so request wall-clock above the extrapolated estimate
rather than at it. Peak GPU memory from a canary is the number that decides which cards are
eligible -- a 20 GB job cannot reliably share a 24 GB card with anyone else's work.

## Account / fair-share mediation

If a job (or array tasks) sit `PD` (pending) longer than the queue's normal wait, check *why*
before assuming resources are just busy:

```
squeue -j <id> -o "%i %T %r"
```

- Reasons like `Resources`, `Nodes_required`, `ReqNodeNotAvail` -- genuinely waiting for hardware
  to free up. An account switch won't help; wait or reduce the request.
- Reasons like `QOSMaxNodePerUserLimit`, `AssocGrpCPUMinutesLimit`, `QOSGrpCpuLimit` -- a hard cap
  tied to the account/QOS the job was submitted under, not a hardware shortage. Switching to a
  *different* account you have access to, with a different cap, unblocks this even if hardware is
  free right now (seen directly: 146-way concurrency capped by `QOSMaxNodePerUserLimit` under
  `mrapsoma_prometex` while other accounts had headroom).
- Reason `Priority` -- the job is schedulable but other jobs (yours or others') rank ahead of it.
  This is where fair-share matters directly: your priority *within* an account depends on that
  account's fair-share factor, which drops the more it's been used recently relative to its share.

**Check fair-share standing across your own accounts:**

```
sshare -U --format=Account,FairShare,RawShares,NormShares,EffectvUsage
```

`FairShare` ranges 0-1; closer to 1 means better remaining priority (that account's recent usage
is low relative to its allocated share), closer to 0 means it's been heavily used and new jobs
under it will queue behind everyone else's. Real example from this cluster:

```
Account               FairShare
mrapsoma_prometex      0.001107   <- heavily used, low priority
rgottar1_owkin_spatial 0.827001   <- plenty of headroom
rgottar1_spatial       0.808558   <- plenty of headroom
```

**Mediation**: if a job is pending with reason `Priority` (or a QOS/Assoc limit reason) under your
default account, and `sshare -U` shows another of your accounts with a meaningfully higher
`FairShare`, resubmit under that account instead (`sbatch --account=<better-account> ...`) rather
than waiting it out on the default. Only switch to an account you're actually authorized/expected
to charge to -- when in doubt which one that is, ask rather than guess, since this is a billing
decision, not just a scheduling one.

## Archiving a job's outputs

Owned by the `artifacts` skill, not here: it governs anything a run writes, not only Slurm output.
The short version is that archiving is approval-gated, takes one explicit path, is never swept, and
that liveness is answered by `squeue`/`sacct` rather than inferred from the filesystem -- a sweep
over "has config.json, lacks summary.json" once killed a running job at 68% of a 3.25 GPU-hour run,
because those files are written at a run's start and end and so match a live job exactly.

## Why this is a skill, not project docs

Submission mechanics (snapshotting, canary discipline, archiving policy, account/fair-share
routing) are identical regardless of what a given project computes -- the same failure modes
(relative paths breaking under a snapshot, a shared environment mutating under a running job, a
hand-invoked canary missing real fan-out plumbing, a sweep archiving a live run, one account's
fair-share tanking from unrelated jobs) recur on any project on this cluster.

It lives in this project's `.claude/skills/`, not in a user-level or global location: a skill that
is only present where the repository is present cannot drift out of sync with the code it
describes, and a clone of the project brings its own operating instructions with it. Improvements
propagate to other projects through the `init` template remote (`docs/reference/template-updates.md`), which
is a reviewed cherry-pick rather than an ambient sync -- so a project can hold a deliberate local
adaptation instead of being silently overwritten.

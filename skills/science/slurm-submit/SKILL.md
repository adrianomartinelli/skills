---
name: slurm-submit
description: Job submission workflow on a Slurm cluster -- QOS/account/partition discovery proven by probe jobs, commit/snapshot/canary/fan-out sequence (canary only when jobs share a submission mechanism, e.g. a fold/seed sweep -- a single independent run skips it), fast_dev_run as a Lightning training job's own pre-submission check, snapshots through the `snapshot` skill, and account/fair-share mediation when jobs won't start. Each job marks its output directory in use with an `IN_USE` file that holds the job ID. Builds on the slurm-ops skill (right-sizing, diagnostics). Use for sbatch, srun, job arrays, sweeps, "submit a job", "run on the cluster".
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

This skill names no real cluster's partitions, QOS, accounts or limits. Every such value below is
an example, marked as one, and is not a default. The values for the cluster you are on come from
the project's `docs/hpc.md`, built by the steps here.

- Before choosing `--qos`/`--account`/`--partition`, check the project's `docs/hpc.md` for a
  persistent inventory of what exists on the cluster, which account/partition/QOS combos are
  proven usable, and quirks that aren't discoverable from a single `sinfo`/`sacctmgr` call (e.g. a
  QOS that silently rejects submissions outside some parameter range).
- If `docs/hpc.md` doesn't exist yet, or lacks the combo you need, don't guess. Discover:

  ```bash
  # which accounts and QOS you are associated with, per partition where the site sets that
  sacctmgr show assoc user=$USER format=account,partition,qos%60,defaultqos -p
  # what each of those QOS allows: wall-clock cap, per-user caps, group caps, priority
  sacctmgr show qos <qos1>,<qos2>,... \
    format=Name%30,Priority,MaxWall,MaxTRESPU%40,MaxJobsPU,MaxSubmitPU,GrpTRES%40,Flags -p
  # partitions: wall-clock limit, GRES, and which accounts/QOS each one admits
  sinfo -o "%P %l %G"
  scontrol show partition <part> | grep -oE "(Allow|Deny)(Accounts|Qos)=[^ ]*|QoS=[^ ]*"
  ```

  A combo is a candidate only when all three agree: your association lists the QOS, the
  partition's `AllowQos`/`AllowAccounts` admit it (`ALL` counts), and the QOS's `MaxWall` covers
  the `--time` you need. To pick a tier, take the QOS with the smallest `MaxWall` that still covers
  the request, read from `sacctmgr show qos`, never assumed from the QOS name.
- **A candidate is not usable until a probe job proves it.** Discovery output is the cluster's
  configuration as `sacctmgr` reports it; it does not prove the scheduler will run your job under
  that combo (see Preflight 3 below: `sbatch` accepts QOS the partition then refuses). `sbatch
  --test-only` is not proof either: it estimates a start without running anything. For each combo
  the project will actually use, submit the smallest job that partition accepts:

  ```bash
  sbatch --account=<acct> --partition=<part> --qos=<qos> --time=00:01:00 --mem=100M \
    --cpus-per-task=1 [--gres=gpu:1] --job-name=probe-<qos> --output=/dev/null --wrap='true'
  sacct -j <id> -X -n -P --format=JobID,Account,Partition,QOS,State,ExitCode,Start,NodeList
  ```

  The probe passes only when `sacct` shows `COMPLETED`, exit `0:0`, and the same `Account`,
  `Partition` and `QOS` you requested. Slurm records what it actually charged and scheduled, so a
  silent substitution shows up here. A probe still pending with a reason that names permission
  (`QOSNotAllowed`, `Job's QOS not permitted to use this partition`, `InvalidAccount`,
  `PartitionConfig`) means the combo is not usable: `scancel` it and record that. A probe pending on
  `Priority` or `Resources` has proven nothing yet; record it as unverified rather than wait
  without bound.
- Probe only the combos the project will submit under, not every combination discovery lists.
  A probe on a GPU partition (where `--gres` is mandatory) or under a privileged QOS still charges
  the account, so ask the user before probing those, as for choosing an account to charge.
- Write the result to `docs/hpc.md` before the real submission: one table row per combo with the
  QOS limits from `sacctmgr show qos`, and an evidence column holding the probe's job ID, date and
  `sacct` line, or "unverified" / "refused: <reason>". A row with no probe evidence is not usable.
  Add a running "quirks" list below the table, so the next session or agent doesn't redo the same
  exploration.
- Treat `docs/hpc.md` as living: when a submission fails for a QOS/partition/account reason not
  yet recorded there, add a one-line note once it's resolved. A QOS or partition change on the
  cluster makes old evidence stale, so re-probe a combo when a real job under it is refused.

## Commit -> snapshot -> canary -> fan-out sequence

> [!CAUTION]
> **Never point a job at the live checkout.** A queued job reads the working tree when it *starts*,
> not when it was submitted, so commits that land during the queue wait silently change what it
> runs. Steps 1 and 2 below are the fix.

Combines `slurm-ops`'s "canary before fan-out" with the `snapshot` skill into one recipe.

**Already in a snapshot? Then skip steps 1 and 2.** If `snapshot.yaml` is at the root of your
working directory, you run in a finished snapshot (a pinned agent session, a job's own working
directory): submit from it with `--chdir=<that directory>`. The job then runs exactly the commit
you run, so it is already pinned, and `create_snapshot.sh` refuses to run there
anyway. Detect it by `snapshot.yaml`, never by git: a snapshot has no `.git`, so git walks up to
the live checkout and reports the checkout's commit and status, not the snapshot's.

1. **Commit** whatever the job will run. A snapshot extracts a commit, so uncommitted work is
   simply absent from the job.
2. **Snapshot** that commit with the `snapshot` skill's `create_snapshot.sh --log <name>`, from the
   project root. It prints the snapshot path; `<name>` is the script or skill submitting the job
   and groups its logs under `.logs/<commit>/<name>/`. The `snapshot` skill owns why snapshots
   exist, the layout, the logs, and how a job runs in one. A job submitted from inside a snapshot
   (a pinned agent's own job) runs in that snapshot and skips this step.
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
   sbatch --account=<acct> --partition=<p> --qos=<qos> --gres=gpu:1 --time=<h>:00:00 \
     --chdir=<snapshot> --job-name=fold-0 \
     --output=<repo>/.logs/<commit>/train/%j-%x.out --error=<repo>/.logs/<commit>/train/%j-%x.err \
     --wrap="pixi run --frozen --no-install python <entry point> --fold=0 ..."
   ```

   **`--frozen --no-install` is not optional**, and both flags are written out: the jobs of a sweep
   start together in one snapshot, and a plain `pixi run` would install into its environment from
   each of them at once (the `snapshot` skill, "Why snapshots exist").

   **A variable reaches the job only through `--export`.** A cluster can set `SBATCH_EXPORT=NONE`
   in the login environment (record it in `docs/hpc.md`), and then a `VAR=x sbatch ...` prefix is
   dropped with no error. Pass it as `--export=VAR=value`, without `ALL`: `ALL` brings back the whole
   submitting shell's environment, a live checkout's pixi activation included. The job needs no
   variable to know its commit: it runs in the snapshot, whose folder name is the commit.

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

## Wait for the job: `sbatch --wait` in the background, Monitor while it queues

An agent that submits a job whose result it needs must be woken when the job starts and when it
ends. Seen directly: agents submitted with plain `sbatch`, ended their turn, and never continued,
because nothing was left to wake them. Use both of these, per job:

1. **The end: `sbatch --wait` as a background shell call.** It blocks until the job ends and exits
   with the job's exit code (0 done; non-zero failed, killed for memory or time, or cancelled). A
   background call wakes the session when it exits. Its first output line names the job ID; read
   it from the background output file. Then `sacct -j <id>` says how the job ended.
2. **The queue: the Monitor tool on that job ID.** `--wait` says nothing while the job is pending,
   and a job can wait for hours (fair share, a full partition, a per-user cap). A loop that prints
   a line while the job is pending, and ends when it leaves PENDING, wakes the session each time:

   ```bash
   while [ "$(squeue -h -j <id> -o %T)" = PENDING ]; do
     echo "pending $(squeue -h -j <id> -o '%r start=%S')"; sleep 600
   done; echo "left the queue: $(squeue -h -j <id> -o %T)"
   ```

   On each line, decide: keep waiting, or `scancel` and resubmit where it starts sooner (another
   partition or QOS, fewer resources, CPU instead of GPU for a model fast enough there).
   `slurm-ops` covers why a job is pending.

For a fan-out, do both for each job. Do not use `/loop` or cron wakeups for this: a headless
session (`claude -p`) exits when its turn ends with nothing running, before a wakeup fires; a
background call or a Monitor keeps it alive (tested 2026-11-06).

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
directory. Example, seen on one cluster: six GPU jobs all carrying `Requeue=1`, of which the
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
that writes the file whole instead of appending is the cure: a restart then replaces the rows.

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

A start estimate a year or more away is the scheduler saying the request cannot be satisfied on
that partition. Treat it as an abort signal and resubmit elsewhere rather than waiting.

**3. QOS acceptance is not QOS permission.** `sbatch` will happily accept a `--qos` that the
partition then refuses, leaving the job pending forever with
`Job's QOS not permitted to use this partition`. Submission succeeding proves nothing. A
multi-partition `--partition=a,b` list needs a QOS every listed partition allows. Enumerate before
submitting:

```bash
scontrol show partition <part> | grep -o "AllowQos=[^ ]*"
```

`check-qos.sh <partition>[,<partition>...] [<qos>] <time>` (next to this file) makes the check one
call, in front of `sbatch` with `&&`. It exits non-zero when a listed partition does not allow the
QOS, when no `--qos` is given and the account's default QOS is not allowed, when the QOS is not in
the account's QOS list, and when `--time` is over the QOS's `MaxWall`. That last one matters on a
cluster with `EnforcePartLimits=NO`: a QOS without `DenyOnLimit` does not reject an over-long
`--time` either, and the job pends forever with `QOSMaxWallDurationPerJobLimit`.

Then take the combo's probe evidence from `docs/hpc.md` (the inventory section above); a combo with
none gets a probe first. QOS naming and tiers are site policy, so read each QOS's `MaxWall` from
`sacctmgr show qos` instead of inferring it from the name. (Example from one cluster, not a
default: QOS names were per-hardware, such as `l40s-1day` and `h200-6hours`, the tiers were
`30min / 6hours / 1day / 1week`, and with no 8h tier a 7-hour job needed the `1day` QOS.) A QOS
permitted everywhere may exist but be a privileged allocation (higher priority, much longer wall);
treat using one as an entitlement decision for the user, like choosing an account to charge.

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
  free right now (example, seen on one cluster: a 146-way sweep capped by
  `QOSMaxNodePerUserLimit` under one account while the user's other accounts had headroom).
- Reason `Priority` -- the job is schedulable but other jobs (yours or others') rank ahead of it.
  This is where fair-share matters directly: your priority *within* an account depends on that
  account's fair-share factor, which drops the more it's been used recently relative to its share.

**Check fair-share standing across your own accounts:**

```
sshare -U --format=Account,FairShare,RawShares,NormShares,EffectvUsage
```

`FairShare` ranges 0-1; closer to 1 means better remaining priority (that account's recent usage
is low relative to its allocated share), closer to 0 means it's been heavily used and new jobs
under it will queue behind everyone else's. Example output (illustrative account names and values):

```
Account               FairShare
<acct-a>               0.001107   <- heavily used, low priority
<acct-b>               0.827001   <- plenty of headroom
<acct-c>               0.808558   <- plenty of headroom
```

**Mediation**: if a job is pending with reason `Priority` (or a QOS/Assoc limit reason) under your
default account, and `sshare -U` shows another of your accounts with a meaningfully higher
`FairShare`, resubmit under that account instead (`sbatch --account=<better-account> ...`) rather
than waiting it out on the default. Only switch to an account you're actually authorized/expected
to charge to -- when in doubt which one that is, ask rather than guess, since this is a billing
decision, not just a scheduling one.

## Mark a job's output directory in use

A running job writes a marker file `IN_USE` into its output directory, the run root below
`OUTPUTS_DIR`. It writes the marker before its first artifact and deletes it as its last step. The
`delete` skill skips every path with a marker at, above or below it. A sweep over "has config.json,
lacks summary.json" once deleted the output of a running job at 68% of a 3.25 GPU-hour run. A run
writes those files at its start and end, so they match a live job exactly. The marker exists only
to show a live job.

The marker holds the job ID, so that an agent can find the job:

```
job_id: 123456
job_name: train-fold0
started: 2026-11-05T14:02:11+01:00
```

Write it in the code that creates the run root, and delete it in a `finally`. Get the job ID from a
`Settings` field (`slurm_job_id: str | None = None` reads `SLURM_JOB_ID`, CFG-2). Write no marker
when the field is `None`.

```python
marker = paths.root / "IN_USE"
marker.write_text(f"job_id: {settings.slurm_job_id}\njob_name: {job_name}\nstarted: {now}\n")
try:
    run(cfg, paths)
finally:
    marker.unlink(missing_ok=True)
```

A job that Slurm kills with `SIGKILL` (out of memory, the end of the time limit) leaves a stale
marker. `sacct -j <job_id> -X -n -o State` shows whether the job ended. A requeued job keeps its
job ID and writes the marker again.

## Why this is a skill, not project docs

Submission mechanics (snapshotting, canary discipline, the in-use marker, account/fair-share
routing) are identical regardless of what a given project computes -- the same failure modes
(relative paths breaking under a snapshot, a shared environment mutating under a running job, a
hand-invoked canary missing real fan-out plumbing, a sweep archiving a live run, one account's
fair-share tanking from unrelated jobs) recur on any project on any Slurm cluster. What does
differ per cluster (its partitions, QOS, accounts and limits) lives in each project's
`docs/hpc.md`, not here.

---
name: slurm-ops
description: Cluster resource right-sizing and health/queue diagnostics -- canary measurement before fan-out, inspecting overall queue state (which partitions are full, who's running/pending what, why jobs are stuck cluster-wide), triaging a job that will not start, and stopping a run that is already going. Pair with slurm-submit, which owns how a job is actually submitted. Use for "how much memory/time", "why is my job pending", sizing an sbatch, "how many jobs can I run at once", "cancel this job", "kill the run", "stop a run early".
---

# slurm-ops

Two responsibilities, both cluster-level, neither project-level:

1. **Resource right-sizing.** Before submitting a new job class, measure it (a canary run: one
   job, not a fan-out) and record wall time / memory / cpu from `sacct -j <id> --format=...` or
   `seff <id>`. Never guess a `--mem`/`--time` from vibes; never copy another job class's numbers
   without checking they're actually the same shape of work. Canary before fan-out: one test job
   per task/dataset first; if it's green, fan out.

2. **Health / queue diagnostics.** `squeue`, `sinfo`, `sacct` triage for stuck, pending, or failed
   jobs: partition health, why a job is PD (priority vs. resources vs. dependency), account/QOS
   limits. For diagnosing why *your own* job is stuck (as opposed to general queue observability
   below), see `slurm-submit`'s "Account / fair-share mediation" section instead of repeating that
   here. Ending a run you already have -- as opposed to one that will not start -- is "Stopping a
   run" below.

## Inspecting the queue: which partitions are full, who's running what

**Per-partition CPU state** (`sinfo`'s raw `CPUS(A/I/O/T)` column is allocated/idle/other/total,
but only per node-state row, so a partition split across `mixed`/`idle`/`allocated` rows doesn't
give one number, so sum it):

```
sinfo -h -o "%P %C" | awk -F'[ /]' '{alloc[$1]+=$2; idle[$1]+=$3; other[$1]+=$4; total[$1]+=$5} \
  END {for (p in total) printf "%-12s alloc=%-6d idle=%-6d total=%-6d busy=%.0f%%\n", \
  p, alloc[p], idle[p], total[p], 100*alloc[p]/total[p]}' | sort -k5 -rn
```

A partition at or near 100% busy isn't necessarily a problem. It means new jobs there will queue
behind current usage (check `sinfo -o "%P %a %l %D %T %C"` for node counts/states, e.g. some nodes
under `maint` or `fail*` explains reduced capacity without anyone's jobs being at fault).

**Who's running/pending, and how many jobs each:**

```
squeue -o "%.10u %.2t" -h | sort | uniq -c | sort -rn
```

**Why jobs are pending, cluster-wide** (not just yours; useful for "is the queue backed up in
general or is it specifically my account"):

```
squeue -t PD -h -o "%.10u %r" | sort | uniq -c | sort -rn
```

Common reasons: `QOSGrpNodeLimit`/`QOSGrpCpuLimit` (an account/QOS cap, not a hardware shortage;
see `slurm-submit` for switching accounts), `Dependency`/`DependencyNeverSatisfied` (waiting on
another job, possibly one that already failed), `Priority` (schedulable, just ranked behind other
jobs), `Resources`/`Nodes_required` (genuinely waiting for hardware).

## User limits: how many jobs per user each QOS / partition allows

Per-user caps live on the QOS, not on the partition. A partition limits jobs per user only
through its partition QOS (`QoS=` in `scontrol show partition`). Your association can add its own
caps on top. List all three; the tightest one wins:

```bash
# per-QOS caps: running jobs (MaxJobsPU), queued+running (MaxSubmitPU), resources (MaxTRESPU)
sacctmgr show qos format=Name%30,MaxJobsPU,MaxSubmitPU,MaxTRESPU%40,MaxWall,Flags%30 -p
# partition -> partition QOS (its limits apply to every job in that partition)
scontrol show partition | grep -oE "PartitionName=[^ ]*|QoS=[^ ]*" | paste - -
# association caps for you (empty = no cap at that level)
sacctmgr show assoc user=$USER format=account,partition,qos%40,maxjobs,maxsubmit,maxtres%30 -p
# your current usage against those limits, per QOS
squeue -u $USER -h -o "%q %t" | sort | uniq -c
```

Read the output as a table of QOS -> max concurrent running jobs per user (`MaxJobsPU`). An empty
field means no cap at that level, not unlimited overall: check the partition QOS and the
association too. `MaxTRESPU` often binds first (e.g. `gres/gpu=4` caps you at 4 one-GPU jobs even
with `MaxJobsPU=10`). When a partition QOS and the job's QOS both set a limit, the partition QOS
wins unless the job QOS has the `OverPartQOS` flag. Jobs held by these caps show as
`QOSMaxJobsPerUserLimit`, `QOSMaxGRESPerUser`, `AssocMaxJobsLimit` in `squeue -t PD -o "%r"`.

If `sacctmgr` shows nothing (some sites hide it via `PrivateData`), try
`scontrol show assoc_mgr users=$USER flags=qos,assoc`, which also shows current usage next to each
limit as `Limit(Used)`. Record the result in the project's `docs/hpc.md` with the rest of the
inventory (see `slurm-submit`), not in this skill.

## Stopping a run: graceful before `scancel`

`scancel` is a SIGKILL after a short grace period, and a training job usually writes its
evaluation and its summary *after* the fit loop returns -- so killing a run throws away exactly
what you wanted from it: a checkpoint you can still score, and a record of how far it got. Three
ways a run can end, and what each leaves behind:

| how it ends | what still runs in-process | what survives |
| --- | --- | --- |
| `scancel` (SIGKILL) | nothing | periodic checkpoints only |
| SIGTERM (walltime, `--signal=B:TERM@600`) | the exception path | + a final checkpoint |
| a stop sentinel (`should_stop`) | the whole normal exit path | + eval, + summary |

Choose by the *reason*, not by which command you remember. Stopping because the loss is flat, the
run is clearly not learning, or the cell has been superseded is a scientific judgement -- which is
exactly the case where you want the run's own evidence for it, so use the sentinel. Stopping
because the job is wedged, OOM-looping, running the wrong code, or holding a reservation you need
back is operational, and `scancel` is correct.

The mechanism, where a project has it: a callback polls a path off the run's managed-paths class
once per batch and sets `trainer.should_stop` when it appears, recording the file's contents in
the run's summary as the reason it stopped. Look for a `stop_file` (or equivalent) on that class;
if the project has none, `scancel` is all there is and the lost evaluation is the price.

```bash
echo "loss flat since step 4000" > <outputs_dir>/<run identity>/.STOP   # keeps eval + summary
scancel <jobid>                                                        # keeps neither
```

Two limits worth knowing before you rely on it. A sentinel is only read at a batch boundary, so a
job that is *hung* rather than unproductive will never see it -- that one is a `scancel`. And the
job still occupies its allocation until the run finishes writing, which for a run with a real
evaluation pass is minutes, not seconds; if you need the nodes back this instant, that is the
operational case again.

## Standing account/partition policy

- Accounts, partitions, QOS and their limits are per cluster and are not recorded in this skill.
  They live in the project's `docs/hpc.md`, discovered and proven by probe jobs as `slurm-submit`'s
  "QOS/account/partition inventory" section describes.
- Partitions: never use an interactive/login partition for CPU-only batch work. Use the batch CPU
  partition even for jobs that could technically run on login-adjacent interactive nodes.

## Why this is a skill, not project docs

Every project on a Slurm cluster hits the same three questions -- "how big a job is this," "is my job
stuck," "which partition/account do I even use" -- and the answers don't depend on what the project
computes. Keeping this as a skill instead of copy-pasted project docs means one fix here fixes it
everywhere it's synced, instead of N stale copies drifting apart.

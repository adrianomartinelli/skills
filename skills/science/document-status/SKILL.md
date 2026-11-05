---
name: document-status
description: Record finished work where it belongs -- open work and runs on GitHub issues, findings, decisions (ADRs), lessons, status -- keeping each file's shape. Use after a fix, a run, an experiment or a decision, for runs that finished, failed or were abandoned without a write-up, and on "update the docs", "log this", "write up that run", or end-of-task wrap-up.
---

# document-status

`AGENTS.md` "Progress tracking" says what each record is for; this skill is how to write to it.

## 1. Read what is already recorded

`docs/status.md`, the open issues touching the work (`gh issue list --state open --json
number,title,labels`), and the end of `docs/findings.md` and `docs/retrospective.md`. Routing
depends on what exists: a run already on an issue gets a comment or a close, not a new issue.

Then look for dangling runs: every open `experiment` issue whose job has finished, failed or been
abandoned since its last comment (`sacct -j <id>`, the run's outputs). Write each one up, not only
the run you were told about. Done when every open `experiment` issue's last comment matches its
job's real state.

## 2. Route each piece to its record

One update often lands in several records (a finished run closes its issue, adds a finding and
moves the status table); write each piece where it belongs.

- **Open work** (a deferred item, a bug found, a follow-up, an experiment to run): a GitHub issue,
  as `docs/agents/issue-tracker.md` says, with one category and one state label
  (`docs/agents/triage-labels.md`). An experiment is a sub-issue of the issue it decides.
- **A run in flight**: a comment on its experiment issue (job IDs, config, canary sizing, what went
  wrong).
- **A finished experiment**: close its issue with a comment giving the result and the finding it
  added; the parent closes with the decision.
- **A finding** (`docs/findings.md`): a claim about the data, a model or a method, backed by a run
  or check a reader can repeat. Next free `F<n>`, then the claim as the heading, its evidence
  (config, command or job) and date, and a closing `**Status:**` line saying how far it holds.
- **A decision** that is hard to reverse, surprising without context and the result of a real
  trade-off: an ADR in `docs/adr/`, next number, the domain-modeling skill's `ADR-FORMAT.md`.
  A decision missing any of the three needs no record.
- **A process lesson** (what to do differently next time, transferable beyond this project's file
  names): `docs/retrospective.md`, "Open lessons", next number. A lesson that has become a check, a
  rule or a skill moves to "Became a rule" as a one-line pointer, keeping its number.
- **The phase or a headline result changed**: `docs/status.md`, its phase paragraph or results
  table. A single run alone rarely changes it.

## 3. Keep each record's shape

- Write blocking and failure reasons as mechanism-level prose: `blocked by: job 12345 still
  reading these outputs`, `failed: OOM at step 4200, batch_size 64 exceeded 40 GB`.
- Cite by ID (`F<n>`, ADR number, lesson number, issue number) rather than restating; IDs are
  permanent.
- Append within the existing headings; a new heading shape only where the file has none yet.
- Retire a stale doc by moving it to `docs/.archive/`.

## Out of scope

- `WORKTREE.md`: the branch-status protocol (`AGENTS.md`, PRC-1).
- `docs/reference/`: stable facts (resource sizing, cluster recipes), updated when the fact
  changes, not as session state.

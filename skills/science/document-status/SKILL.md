---
name: document-status
description: Use after finishing a chunk of work (a fix, a run, an experiment, a decision) to fold it into docs/status.md, docs/todo.md, docs/experiments.md, docs/retrospective.md, or docs/findings.md -- whichever it actually belongs in -- while preserving each file's required shape. Also covers experiments/runs that finished, failed, or were abandoned without ever getting written up. Trigger on "update the docs", "log this", "record status", "write up that run", or end-of-task wrap-up when docs/ exists in the project.
---

# document-status

See `AGENTS.md`'s "Progress tracking" guidance for what each `docs/` file is *for*. This skill is
the how-to for keeping them updated without breaking their shape.

## Read before writing

In order: `PROJECT.md`, then `docs/status.md` -> `docs/todo.md` -> `docs/experiments.md` ->
`docs/retrospective.md`. Do this even for a small update -- routing depends on what's already
recorded (an experiment already logged as in-flight needs its entry closed out, not a new one
appended).

## Route by kind, not by convenience

Don't default everything into `status.md`. Pick the file the update is actually about:

- **`status.md`** -- current state, what to read first on resume. Update when the overall picture
  changed, not for every individual run.
- **`todo.md`** -- open backlog. `- [ ]` / `- [x]` items, bold status vocabulary, priority expressed
  as section grouping (`## Priority 1/2/3`) or a trailing suffix, never a numeric code.
- **`experiments.md`** -- exact commands/configs/gates for runs, whether in flight, just finished,
  failed, or abandoned. This is the most common gap: a run that completed or died since the doc was
  last touched and never got written up. Check for these explicitly -- don't just add the run you
  were told about, look for others left dangling.
- **`retrospective.md`** -- transferable process lessons (what to do differently next time), not
  what happened this run.
- **`findings.md`** (optional) -- scientific/diagnostic findings about data or model. Give each a
  stable `F<n>` ID the moment it's written so other docs can cite it.

A single update often touches more than one file (a finished run closes an `experiments.md` entry
*and* may add a `findings.md` entry *and* may move a `todo.md` item to done) -- write to each one
it actually belongs in, don't force it into a single file for convenience.

## Preserve each file's shape

- Bold status vocabulary declared once per file (default: `**planned**/**in-progress**/**blocked**/
  **done**/**parked**`, narrowed per file if useful) -- reuse the file's existing vocabulary, don't
  invent a new token.
- Blocking or failure reasons are mechanism-level prose (`BLOCKED: job 12345 still reading these
  outputs`, `FAILED: OOM at step 4200, batch_size 64 exceeded 40GB`), never a bare tag with no
  mechanism.
- Don't restructure existing headings or reorder sections to fit new content -- append/update
  within what's there. Only introduce a new heading shape if the file doesn't have one yet.
- Don't create a `docs/` file this project doesn't already use unless the update genuinely has
  nowhere else to go (e.g. first finding ever -> create `findings.md` matching the schema above).

## Out of scope

- `WORKTREE.md` -- that's the branch-status protocol (`concurrent-sessions` skill), not this skill.
- `docs/reference/` -- stable facts (resource sizing, cluster recipes), not session-resumable state;
  don't fold a status update into it.
- Retiring a stale snapshot: move it to `docs/.archive/` instead of deleting, per `AGENTS.md`.

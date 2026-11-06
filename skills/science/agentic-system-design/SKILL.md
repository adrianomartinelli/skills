---
name: agentic-system-design
description: How to design a workflow that agents operate. Covers commands that run, inspect and decide, fixed config and decision files, and one folder per agent. Also covers agent definitions and skills with hooks, snapshots, the launch of agents, and feedback and log review. Use it before you build or change anything agents operate. Examples are a stage or step, a command or view, a decision file, an agent definition or its hooks, or the setup of agents. Triggers: "design a stage", "add a step", "add a tool/view for agents", "agent workflow", "launch agents", "orchestrate agents".
---

# agentic-system-design

The authority for how a workflow that agents operate is built. `AGENTS.md` governs code, config,
paths, identity and artifacts in general. This skill builds on it and does not restate it. It
governs what an agent sees, calls and may change. How to *read* the views of one workflow is the
skill of that workflow.

Design for the parts that matter: the loop below, the decision contract and agent isolation. Build
only the commands and checks that something uses now. Real use (feedback, log review) decides what
comes next. Less output with optional depth beat complete output every time it was tried.

## The loop

```
input (built once, shared, read-only, hashed)
  -> run    -> artifacts in the agent's folder, one folder per identity
  -> get_*  -> YAML on stdout, figures next to the artifact, both logged
  -> set_*  -> decision file (validated, its reason cites what get_* printed)
  -> run    -> reads the decisions, writes the next artifacts ...
```

> [!CAUTION]
> **Every number a decision rests on was printed by a workflow command, and every figure was
> drawn by one.** An agent that lacks a view says so with `feedback` and decides with what exists,
> or stops. It never computes the view itself. A decision built on ad-hoc analysis looks exactly
> like a good one, and nobody can check or repeat it.

## 1. Commands

A workflow has two CLIs. Each has one subcommand per verb, and each subcommand has its own typed
request model (`AGENTS.md`, CFG-7):

- The agent CLI. It is the only CLI an agent calls.
- The admin CLI. It holds the setup of agents (section 7) and the entrypoints that only jobs call.

| kind | CLI | does | writes |
|---|---|---|---|
| `init` | admin | sets an agent up: input, commit, compute, brief | the agent's fixed files |
| `create_snapshot` | admin | freezes the agent's commit with the `snapshot` skill's script | one snapshot per commit (section 3) |
| `launch` | admin | starts the agent as its own headless session in the snapshot | a binding line, the session's final output |
| `status` | agent | the entry point: state, `last_run`, stale decisions, `next` (what to call) | nothing |
| `run` | agent | processing: segment, cluster, measure ... | artifacts, one folder per identity |
| `get_*` | agent | prints what an artifact holds, or a metric measured on it, and may draw a figure | figures next to the artifact, named by content, drawn once and reused |
| `set_*` | agent | records one decision | the agent's decision file, under a lock, after validation |
| `feedback` | agent | reports friction (section 6) | the agent's `feedback.jsonl` |

- **Typed and strict.** `--help` shows exactly the schema of that command. An unknown flag is an
  error. A generic `show --view X`, whose flags are the union of all views, fails here: the agent
  cannot tell that a filter was ignored.
- **Small by default, depth on request.** Use three levels:
  1. an overview: one row per item, only the columns that settle most cases
  2. a detail command for named items (`--ids`)
  3. flags that add columns where they are needed

  For example `get_clusters`, then `get_cluster --ids`, and `--markers` to add columns.
  - **The default is what the next step needs.** A view that prints the same large block on every
    call teaches the agent to skip its output, and to try options that do not exist. `status`
    prints state, `next`, `last_run`, counts and names, never a config dump: one `get_config` view
    prints the config.
  - **Attention rows, not pages.** An overview shows the rows that need a decision (flagged,
    undecided, stale); a table that fits under the cap shows every row. `--ids` shows named rows,
    one `--all` flag every row. No offset: an agent that pages lacked the right default.
  - **One cap, always announced.** One `--limit` default for every view, lifted by `--all`. Every
    cut table or list, also inside a detail view, says how many rows it dropped and which flag
    shows them.
  - **One name per concept.** `--ids` always selects the view's own rows, in every view of every
    workflow. A flag name has one type everywhere.
- **Reproducible evidence.** A `get_*` prints the same output for the same artifact, arguments and
  commit. Inspection never requires an edit of fixed config. When the decision is "choose k", a
  `get_* --k` shows the result of any k (counts, a gallery).
- **Refusals raise.** The last line says what is wrong and what to change. The state stays as it
  was.
- **Done is the last file.** `run` writes the file that marks a unit as done last. A unit without
  it is not done, and the next `run` writes the unit again (`AGENTS.md`, ART-2: the project's own
  files can be rewritten).
- **Long runs.** `run` submits through the compute fixed at `init`: a command for the job
  scheduler of the machine, or in place where there is none. The agent starts `run` in the
  background, waits, and then reads `status`. It never reads scheduler logs.
- **Literal invocations.** Document every command as one full literal invocation, one per Bash
  call, with no shell variables, loops or chains. Isolated sessions refuse those, and they make the
  call log hard to parse.
- **Grow from use.** Add a command when feedback or a log review shows the need. Delete a command
  that no agent used in a round.

### Two readers, agent first

- **One call serves the agent and the human.** The agent decides from the printed numbers; the
  same call draws the figure a human would read the same data from. Design the numbers for the
  decision first, then ask what a human would have plotted to see it, and draw that too. The agent
  may look at the figure as well; the human may read the numbers.
  - The figure is the natural view, not a copy of the printed numbers. It may show more: the agent
    reads quantiles, the human a histogram; the agent reads median and range per cluster, the human
    a box plot with each value as a strip. Both come from the same data in the same call.
  - The printed numbers are never replaced by the figure. Every number a decision rests on is
    printed, so the agent never reads a value off a picture.
  - When the image is the data (cell crops, a segmentation overlay, a channel's signal), the image
    is the one artifact both read. Do not add statistics computed from it as an agent version.
  - No figure when it adds nothing: names, IDs, state, or a table small enough for a human to read.
- **One question per figure.** Put two panels in one figure only when they are read together (a
  heatmap and its cluster sizes); otherwise draw separate files. Several plain figures beat one
  figure of five plots. An agent must be able to read every figure: keep it under 2 MP and 2000 px
  on the long edge. A larger image is downscaled when it is read, and points and small numbers are
  lost. Cap a figure's width when it grows with the data; split it into files when the cap is hit.

For example `get_marker` prints each cluster's `[median, pct_step, pct_table]` and draws
`markers/<marker>.png`; `get_composition` prints each sample's share per group and draws the
stacked bars; `get_cluster --ids` prints each marker's `[median, pct_step, pct_table]` and draws
`clusters/<id>.png`, the cluster's cells against the rest of the step per marker. Its three
`top_samples` stay a table: a human reads three numbers faster than a bar plot.

## 2. Decisions

- **One file per agent.** The decision file of an agent holds only its decisions. Every field it
  may set has a command, notes and targets included. Nobody edits the file by hand, and a hook
  refuses `Edit` and `Write` on it (section 5).
- **Typed.**
  - The model is pydantic with `extra="forbid"` and typed values. Do not use a free `dict` merged
    with `update`: stale keys stay in it and still count toward identity.
  - Reason codes are enums in code, not in a skill.
  - A JSON schema is committed next to the skill of the workflow, and a test keeps it equal to
    the model.
- **Reasons cite evidence.** Every call has a required `reason`. It names the numbers the call
  rests on and the command or figure they came from. It does not repeat the value.
- **Calls are pinned.** Each call stores the identity of the artifact it was made on. When that
  artifact is replaced (an upstream change), the call is **stale**. A stale call is never applied,
  `status` lists it, and only a new `set_*` call clears it. There is no "re-confirm" command: a
  command that clears staleness without new evidence is a rubber stamp.
- **Revisions keep history.** A change to a current call goes through a revise command. It records
  the old call and a reason, and the file keeps that history.
- **Identity counts values only.** The identity of a downstream run includes the values of current
  calls only. Reasons, notes and timestamps do not count.
- **Defaults.** One `--default` call covers all items that share a reason, instead of N identical
  entries.
- **Schema changes.** Change the model. A file of an older schema is refused with what to change.
  Never add a shim.

## 3. Fixed config, inputs, code

- **Fixed at `init`.** `init` writes what defines a task, once. The agent cannot change it: the
  input and its parameters (such as normalization), the candidates a decision chooses from,
  compute and the brief. The agent reads them through `status`.
- **Every parameter has an owner.** A parameter is either fixed by a human, with a comment that
  says why, or an agent decision with a view and a `set_*` command. A threshold in config without
  either is a gap. Find it in the stage spec (section 8), not in a review.
- **Inputs enter through a build command.** It validates the input (keys, columns, dtypes, NaN,
  value ranges). Then it writes a shared, read-only input folder once, with the tables and a
  `config.yaml`. The `config.yaml` holds the sha256 of each table and the provenance: the upstream
  workflow, the decision file applied and the commit. All agents of a stage read the same built
  input. A stage hands over to the next stage only through the build command of the next stage.
- **Hash at the boundary.** Hash inputs where they enter (the build). Downstream, run identities
  are enough. Do not hash every file a command reads.
- **Method parameters are identity.** Every parameter that changes a number an agent decides on is
  a field of the run identity (graph size, cluster bounds, stability resampling). This includes
  code constants. The commit pin covers one agent. The identity and the embedded config
  also serve comparisons across agents and commits, and a commit hash alone cannot answer those.
  Limits that only refuse, and presentation parameters (figure subsample sizes), stay with the
  commit.
- **A step reads its config, it is not handed loose arguments.** A step function takes the config
  (sub-)model that owns its parameters and reads them itself. Defaults live only on the model:
  a function parameter a config owns has no default, so a missed pass is an error, not a silent
  default that the identity does not show. Derived values (a mask, a summed channel) are computed
  inside the step, never passed in by the caller. Pass the narrowest sub-model, not the whole
  config: what a function reads stays visible. Pure math primitives keep explicit arguments.
- **Pin the code.** `init` records the git commit and refuses a dirty tree. The dirty check counts
  tracked files only (`--untracked-files=no`), so one stray file cannot block every agent. Every
  later command refuses code of another commit. It reads its own commit from the `commit` key of
  `snapshot.yaml`, and from git only in the main checkout or a git worktree (the `snapshot` skill,
  "The commit comes from `snapshot.yaml`").
- **Run from a snapshot.** Agents, humans with an agent's task, and the jobs they submit run from
  the snapshot of the pinned commit, never from a live checkout. The `snapshot` skill owns how:
  why, the layout in `<repo>/.snapshots/<commit>/`, the logs, and `create_snapshot.sh`. The
  admin CLI's `create_snapshot` wraps that script with the agent's commit and name
  (`--commit <commit> --log <agent>`). It does not implement the steps again. Every `pixi run` in
  the snapshot, the agent's and its jobs', is `pixi run --frozen --no-install`. A job submitted
  from the snapshot runs in it and needs no snapshot of its own.

## 4. Layout: one folder per agent, browsable by a human

```
<repo>/.snapshots/<commit>/     # code and frozen environment of one commit (create_snapshot)
<outputs>/<workflow>/
  inputs/<input>/               # built once, read-only, shared by all agents
    <tables>.parquet
    config.yaml                 #   filled-in config, sha256 per table, provenance
  agents/<agent>/               # created by init: all this agent did, and nothing else
    setup.yaml                  #   fixed: input, commit, compute, kind (agent|human), read-only
    brief.md                    #   optional extra instructions, read-only
    decisions.yaml              #   its decisions, set_* only
    runs/<step>/<identity>/     #   what run wrote: config.yaml, tables, figures/
    runs.jsonl                  #   its job log: the events of every run (run, run_job)
    calls.jsonl                 #   every tool call of its sessions (hook)
    sessions/<session-id>.json  #   the final output of each launched session
    feedback.jsonl              #   its feedback
    report.md                   #   its final report
  bindings.jsonl                # session id -> agent, written by launch before the session starts
<outputs>/reviews/<round>.yaml  # log reviews (section 6); a round can span workflows
```

- **Where an agent writes and reads.** An agent writes its report by hand, and all else through
  commands. It reads only its own folder and its input. It does not read the folders of other
  agents, `docs/` or the logs. This keeps agents independent and lets a task run blind.
- **No scratch space.** Every input to a command is an argument, so an agent needs no scratch
  space. The agent definition forbids the session scratchpad. Parallel agents that shared one
  overwrote each other's helper scripts and ran the wrong copy.
- **Built for a human to browse.** Names are readable down to the step, and a hash appears only at
  the leaf. Every artifact folder holds its own `config.yaml`. Figures are PNG files next to the
  table they show. YAML holds everything a person reads. `status` and `get_*` print the paths they
  refer to.
- **Humans use the same commands.** `init --kind human` sets a human up. A human works in the
  snapshot like an agent, so the decisions of a human are recorded the same way.
- **Paths come from the managed-paths classes** (`AGENTS.md`, PTH-1).

## 5. Agent definitions, skills and hooks

Each role is `.claude/agents/<role>.md`, and each workflow has a skill. Both can declare
restrictions and hooks in their frontmatter, with a different scope:

| where | restricts tools | hooks run |
|---|---|---|
| agent definition | `tools:` (allowlist), `disallowedTools:` | for every call of the agent, only while it runs, also as the main thread (`claude --agent <role>`) |
| skill | `disallowed-tools:` while the skill is active (`allowed-tools:` only pre-approves) | from the moment the skill is invoked to the end of the session |

The agent definition sets the boundary of a role. Use skill hooks for a session that runs the
workflow by hand (a human): the skill of the workflow declares the same edit refusal. Frontmatter
hooks run only in a folder that Claude Code trusts, and a folder inside a trusted one counts.
Headless mode (`-p`) skips the trust dialog but not this rule. Outside a trusted folder the agent
runs and its hooks are skipped, with no error.

- **Body.** Say who the agent is and the one CLI it calls, in full literal form. Say where it
  writes, that it decides only from command output, and that it gives `feedback` when friction
  happens. Say that it is done when `status` says `done`, and that it then writes `report.md`.
  Give the shape of its final message.
- **`tools:` allowlist.** `Bash, Read, Glob, Grep`, and `Write` only for a role that writes its
  report by hand. No web tools, no notebooks.
- **`hooks:` in the frontmatter.** They run only while the agent runs:
  - **PreToolUse** on `*`: refuse, with exit 2, every call of a session that `launch` did not
    bind. Such a session started some other way (by hand, or as a subagent in a live checkout), so
    it runs on code that nobody pinned. Stderr names `launch`.
  - **PreToolUse** on `Edit|Write|MultiEdit|NotebookEdit`: refuse every file but the report of the
    agent. Stderr names the command that changes the file.
  - **PostToolUse** on `*`: append the call (input and response) to the `calls.jsonl` of the
    agent. Validate each decision file the call changed, and report a broken file with exit 2.
- **Bind by session.** The hook input carries the `session_id`. An agent is the main thread of its
  own session (section 7), so `agent_id` is empty: it only separates the subagents of one session.
  `launch` chooses the session id and appends `{session_id, agent}` to `bindings.jsonl` before the
  session starts. Thus every call, the first included, goes to the `calls.jsonl` of that agent. A
  relaunched agent gets a new session and a new binding line. Its name and its folder stay the
  same.
- **Hooks run the snapshot code.** A hook command starts with `cd "$CLAUDE_PROJECT_DIR"`, the
  folder the session started in: the snapshot of the agent. Hooks inherit the environment of the
  session. Keep hook code small, because it runs around every call.
- **Give the benefit of the doubt.** Block a behaviour with a hook when it is clearly unwanted and
  the hook is simple. Leave the rest to log review. Add a block when a review shows the behaviour
  again. Do not build a shell parser.
- **Project-wide rules.** `permissions.deny` in `settings.json` applies to every session, human
  sessions included. Use it only for what no session may ever do.

## 6. Feedback and log review

- **`feedback` is one command, the same in every workflow.** Its arguments:
  - `--feedback.kind missing_view|unexpected|too_verbose|problem|other`
  - `--feedback.command <cmd>`
  - `--feedback.text "what I wanted, what I did instead"`

  It appends the entry, with time and commit, to the
  `feedback.jsonl` of the agent. An agent gives one point per entry when the friction happens, not
  only at the end. Humans use it too.
- **One log-review command per project** reads the `calls.jsonl` and `feedback.jsonl` of a round.
  It writes `reviews/<round>.yaml` and prints a short summary:
  - **Use:** calls and refusals per command (a high refusal rate is friction, also without
    feedback), how many agents used each command, commands that nobody used.
  - **Deviations:**
    - Bash that is not one workflow command (chains, variables, `python -c`, other scripts)
    - reads outside the agent's folder and input, and writes outside its folder
    - calls that a hook refused
    - a session that named another agent
  - **Feedback**, grouped by kind and command.
- **Close the loop.** Triage the review into issues (`docs/agents/issue-tracker.md`). A change cites the feedback it
  answers. The next review shows whether the friction is gone. Deviations are signals about the
  tools first and about the agents second: an agent that used `python -c` usually lacked a view.
- **A dashboard over the same logs** lets a human review the session of one agent. It needs
  nothing extra from the agents.

## 7. Orchestrator: setup only

For now the orchestrator only sets agents up. It does not read `status`, send messages, compare
agents or hand stages over. A human or a main session can be the orchestrator. It uses the admin
CLI from a clean checkout:

1. `init` each agent: name, input, kind, compute, brief.
2. `create_snapshot` for the commit of the agents. Agents of one commit share one snapshot.
3. `launch` each agent. `launch` returns at once.

`launch` binds a new session id to the agent. Then it starts the agent as its own headless Claude
Code process. The working directory is the snapshot, and the session takes the agent's name:

    claude -p "You are agent <name>." --agent <role> --name <name> --session-id <uuid> \
        --add-dir <agent folder> <input folder> --allowedTools <the role's CLI and file tools> \
        < /dev/null

- The task is on disk: `status` gives the input, the targets and the brief.
- A headless session cannot ask for a permission, so only the pre-approved tools run.
- Never start a role as a subagent of the Agent tool. A subagent runs in the working directory of
  the orchestrator, on the code of that checkout, and the tool takes no working directory. If the
  role is not found, stop. A general-purpose agent instead runs without the hooks and without the
  log.
- The orchestrator never decides and never calls `set_*` for an agent. An orchestrator that does
  the work of an agent works without its hooks, without its log, and not blind.
- To replace a killed agent, `launch` the same name again. The new session continues from the
  decision file: all state is on disk, and `run` skips work whose identity is done.
- One agent per stage, or per independent unit of work in a stage. Several agents that decide the
  same thing, and a consensus between them, are out of scope for now.

## 8. Designing a stage: the spec, then the build order

Write the spec before any code, in the design doc of the workflow, and keep it current:

```
Stage:     <name>: what it produces, in one sentence
Input:     <built input>, from <upstream handoff>, hashed at build
Decisions:
  | decision | owner (fixed/agent) | evidence: command, and what it prints/draws | set command |
Artifacts: <what run writes>, the identity fields
Handoff:   <the next stage's input>
Open:      <what the pilot must answer>
```

Every row of the decisions table needs an evidence command and an owner before anything is built.
If a row has neither, the stage is not designed yet.

Build order:

1. the input build
2. `run`
3. the `get_*` each decision needs, overview first, depth after
4. `set_*` with typed models
5. `status` with `next`
6. the agent definition with its hooks
7. `init`, `create_snapshot` and `launch`
8. the skill, which tells how to read each view
9. tests, one per contract rule: refusal, staleness, schema equal to the model, hook block, a call
   of an unlaunched session refused
10. a pilot with one agent, which checks that its `calls.jsonl` fills
11. log review and feedback
12. changes from what they show

## 9. Tools

`AGENTS.md` ("Preferred tools") names the project's tools. They are repeated here for what each
means in a workflow, because a workflow built on other tools loses the guarantees above:

- **`pydantic`** for every request model, decision file and fixed config. The model is the schema
  that `--help` shows and that validation refuses against (section 1, "Typed and strict").
- **`jsonargparse`** for both CLIs: one subcommand per verb, each built from its request model
  (`AGENTS.md`, CFG-7). No hand-written `argparse`.
- **`pydantic-settings`** for machine settings only (paths, the scheduler). Nothing a decision
  rests on comes from the environment.
- **`marsilea`** for figures: box and strip plots, heatmaps, columns chunked by group, count bars
  on the side. Use plain `matplotlib` only where marsilea has no plotter (a scatter, an image
  grid). Draw at one fixed DPI so the size of a figure is predictable (section 1, "One question
  per figure").
- **`loguru`** for logs of `run` and jobs. A command's stdout holds only its YAML result, so the
  agent and the call log parse it without noise.
- **`pandas` / `pyarrow`** for tables, written as parquet; YAML for what an agent reads or sets.

## Anti-patterns (each one seen in practice)

| Seen | Do instead |
|---|---|
| A note cites per-group numbers that no view printed | Add the view, or decide without it and give `feedback` |
| One generic `show --view` with flags that some views ignore silently | One typed subcommand per view |
| Decision settings as a free dict merged with `update`, dead keys still in identity | A typed model per decision, `extra="forbid"` |
| A "re-confirm" step that clears staleness without new evidence | Stale calls stay inert until a new `set_*` |
| Inspection at one config value only: another value means an edit of fixed config | `get_* --<param>` shows any value |
| Hand edits of a decision file | `set_*` and note commands, and a PreToolUse hook refuses edits |
| Several agents write one shared decision file | One decision file per agent |
| The orchestrator does the work of the agent | `launch` the role, and stop if it is missing |
| Agents spawned as subagents, in the live checkout of the orchestrator | `launch`: a headless session in a snapshot of the pinned commit |
| A snapshot outside the trusted repository: hooks skipped with no error | Snapshots in `<repo>/.snapshots/`, and the pilot checks that `calls.jsonl` fills |
| Agents bound by a parse of their first command, earlier calls lost | `launch` records the session id before the session starts |
| A file written before the slow part of a job blocks every retry | Work in progress is rewritten, and a unit is done by its last file |
| Parallel agents in one scratchpad run each other's helpers | Own folder only, no scratch space |
| Every row of every table printed | Overview, then `--ids`, then flags that add columns |
| `status` reprints every candidate's config on each call; the agent tries `--limit 0` to quiet it | `status` prints state and names; a `get_config` view prints the config |
| A capped list of 112 ROIs; the agent tries a non-existent `--offset` to page | Attention rows by default, `--ids` and `--all` for the rest |
| `ids`, `channel`, `marker`, `rois` for the same selection; a limit of 20 to 60 per view | One flag name per concept, one cap default |
| A threshold or candidate sweep in config that nobody chose from evidence | An owner in the stage spec: fixed with a reason, or an agent decision with a view |
| Commands documented with shell variables and chains | One literal invocation per call |
| A stray untracked file blocks the commit check of every agent | Count tracked files only |

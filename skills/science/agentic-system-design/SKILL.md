---
name: agentic-system-design
description: How to design a workflow that agents operate and humans can run the same way - the workspace an agent works in, the config instances it sets, the tools that run them, the views it reads, the append-only log of its decisions, the export it hands on, and how agents are launched, isolated and reviewed. Use it before you build or change anything agents operate - a stage, a tool or view, a config type, an item command, an agent definition or its hooks, the launch of agents. Triggers - "design a stage", "add a tool/view for agents", "agent workflow", "launch agents", "orchestrate agents".
---

# agentic-system-design

How to build a workflow that agents operate: what an agent sees, calls and may change, and how its
work is recorded and handed on. The project's `AGENTS.md` sets the rules every design follows
(`DES-1` to `DES-7`) and the preferred tools. The `contract-design` skill governs the boundaries
between programs. How to read the views of one workflow is that workflow's skill.

`patterns.md` next to this file holds a runnable code example for each section marked *(P1)* to
*(P7)*. Read the pattern before you build the part.

## Principles

- **Agents have agency.** The agent chooses: its config instances and their names, the values it
  sets, which tools it runs and in which order, which views it reads, when it tries another
  instance, and when it exports. The code offers commands, validates each call, and refuses an
  invalid one. It never chooses for the agent (no automatic selection of a parameter or a channel)
  and never tells it what to do next. A call needs only what its computation needs.
- **Agents decide; tools give them the means.** The state of the work is the decision log and the
  finished outputs, read again by the command that needs them. No code tracks the progress of the
  work.
- **Built for agents, equally easy for humans.** A human runs the same commands in the same
  workspace, reads the same outputs, and decides through the same calls. `--help` shows each
  command's model; folder names, the log and the configs are readable; figures are PNG files; a
  refusal says what to change. A step that is awkward for a human is awkward for an agent too.
- **Every number a decision rests on was printed by a workflow command**, and every figure was
  drawn by one. An agent that lacks a view says so with `feedback` and decides with what exists,
  or stops. It never computes the view itself: a decision built on ad-hoc analysis looks exactly
  like a good one, and nobody can check or repeat it.

## The shape

One session works on one stage, in one folder of its own, the **workspace**:

```
admin launch --stage <s> --workdir <dir> --input '{artifact: path}' --brief <file>
  -> <workspace>/ setup.yaml, brief.md, input/datapackage.json, decisions.yaml (empty)
agent or human:
  init <name> <type>                a config instance of a config type
  set_config <name> <patch>         sets tunable fields, with a reason
  <tool> <name>                     runs the instance -> <workspace>/<identity>/ (manifest last)
  get_* / draw_*                    views: print numbers, draw figures
  set_<item> <name> <ids> <patch>   decisions per item, with a reason, checked by the artifact's schema
  export [<name>]                   validates every artifact, writes export/ for the next stage
```

## Work order

Follow `DES-6` per work package (the core, one stage):

1. **Spec.** For each decision the agent makes: the config field or item command that records it,
   and the view that prints its evidence. A decision without both is not designed yet. For each
   fixed value: why it is fixed.
2. **Contracts.** Config types, artifact schemas, relations between artifacts, the CLI flow, and a
   worked example: the commands, the log entries, the files, the refusals. Review until they agree.
3. **Dummies.** Tools with the real signatures that return small schema-valid artifacts. The worked
   example runs through the real CLI as a test.
4. **Real logic**, one dummy at a time; the worked-example test stays green.
5. **Agent definition and skill**, then **one pilot agent**, then log review and feedback, then the
   changes they show.

## 1. Workspace and launch

- **One session, one stage, one folder.** The workspace holds `setup.yaml` (stage, commit, session,
  who launched it; read-only), `brief.md`, `input/datapackage.json`, `decisions.yaml`, the tool
  outputs, `views/` and `export/`. Everything in it changes through commands. The agent reads only
  its workspace and its input.
- **The launcher chooses where.** The workspace path is the launcher's choice (`--workdir`), with
  the session id as the last folder. The code knows no project layout.
- **The input is a manifest of references.** `input/datapackage.json` lists each artifact the
  stage reads: path, sha256, producer. `launch` validates each artifact against its schema and the
  relations between them. Another input is another workspace.
- **The brief is text.** Everything a human or an orchestrator tells the agent (roles, targets,
  hints, what to choose) is in the brief, in the prompt and copied to `brief.md`. No code reads it.
  The agent acts on it through its commands and cites it in its reasons.
- **`launch` chooses the session id** and starts the agent as its own headless session with that
  id, in a snapshot of the chosen commit (the `snapshot` skill), with the workspace in its
  environment (`WORKSPACE_DIR`). The folder name is the session id, so every call of the session
  belongs to the workspace from the first one on. `admin setup` makes the same workspace for a
  human, without a session.
- **Start a role only with `launch`**, as its own session. A subagent of the orchestrator runs in
  the orchestrator's checkout, on unpinned code, and without the role's hooks.

## 2. Commands

Two CLIs, one subcommand per verb, each with its own typed request model: the **agent CLI** (all
an agent calls; it finds its stage in `setup.yaml`) and the **admin CLI** (launch, setup, and
entrypoints only jobs call). The same two CLIs serve every stage.

| kind | does | writes |
|---|---|---|
| `init` | names a config instance of a type | a log entry |
| `set_config` | patches an instance's tunable fields, with a reason | a log entry |
| tool (a domain verb: `measure`, `segment`, `cluster`) | runs one instance | a tool output, a log entry |
| view (`get_*`, `draw_*`) | prints numbers; draws a figure | figures under `views/` |
| item command (`set_<noun>`, `annotate`) | sets values of named items, with a reason | a log entry |
| `export` | validates and publishes | `export/` and a log entry |
| `feedback` | reports friction | `feedback.jsonl` |

- **Typed and strict.** `--help` shows the request model. An unknown flag or key is an error. Each
  view is its own subcommand with its own flags.
- **Refusals raise.** The last line says what is wrong and what to change. A refused call changes
  nothing. A missing value is not a refusal: the call is accepted and reports `incomplete: [...]`.
- **Small by default, depth on request.** An overview with one row per item and the columns that
  settle most cases; a detail command for named items (`--ids`); flags that add columns. The
  overview shows the rows that need a decision. One cap for every view, announced with how many
  rows it dropped and the flag that shows them.
- **One name per concept.** `--ids` selects a view's own rows in every view; a flag has one type
  everywhere.
- **Reproducible evidence.** A view prints the same output for the same outputs, arguments and
  commit.
- **Literal invocations.** Document every command as one full literal invocation, one per Bash
  call, without shell variables, loops or chains: isolated sessions refuse those, and a literal
  call is easy to review.
- **Long work runs as a job.** The agent submits a tool to the scheduler itself and watches its own
  jobs. The tool's log entry is appended when the call starts, so a failed job stays visible.
- **Grow from use.** Add a command when feedback or a log review shows the need. Delete a command
  that no agent used in a round.

### Two readers

- **One call serves the agent and the human.** The agent decides from the printed numbers; the
  same call draws the figure a human would read the same data from (a histogram where the agent
  reads quantiles). Every number a decision rests on is printed, never only drawn.
- **When the image is the data** (cell crops, an overlay), the image is the one artifact both read.
- **One question per figure**, under 2 MP and 2000 px on the long edge, so an agent can read it.
  Split a figure into files when it grows with the data.

## 3. Configs *(P1, P2)*

- **A config type is a fixed model and a tunable model**, both `extra="forbid"`, combined flat into
  the tool's config. A fixed value is the fixed model's default, in the code: changing it is a
  commit. The tunable model holds what the agent chooses; a field without a default must be set.
  What the user wants chosen goes in the brief.
- **Patches merge per key** in log order (`OmegaConf.merge`), then the tunable model validates the
  result. A field that names items of the input (channels, targets) is checked by its own
  validator against the validation context. Variants are a discriminated-union field
  (`contract-design`).
- **Every parameter has an owner.** Fixed, with a comment that says why, or tunable, with a view
  that shows the evidence for choosing it.
- **A config that reads an earlier output** names it by a field that holds the path to that
  output's `datapackage.json`; the tool checks that the artifacts it needs are listed.
- **Once a tool used an instance, it is frozen.** Another choice is another instance, with its own
  name and its own fields.

## 4. Decisions: an append-only log *(P3, P5)*

- **One `decisions.yaml` per workspace, append-only.** The command writes each entry: the command,
  the instance, the patch, the reason, the manifests it read and wrote (`input`, `output`), `at`,
  and `by` (the session id, or `human`). Whatever a command resolves (the ids a `--default` stood
  for) goes into its entry, so the file is read without searching it. A refused call appends
  nothing. A hook refuses edits of the file.
- **Reasons cite evidence in words**: the numbers the call rests on and the view they came from.
- **A later entry is the revision**, and both entries stay.
- **Item decisions are patches validated by the artifact's own schema.** The artifact's state is
  its items with every value null and every logged patch applied, per key, in log order. A call
  validates the rows it names: `not_nullable` is incomplete, any other failure refuses. Export
  validates the whole table with the same schema.
- **A call applies to the output it read.** Each entry records that output, so a call made on one
  output never applies to another.
- **Defaults.** One `--default` call covers the items that have no value yet; its entry lists them.

## 5. Tool outputs *(P4)*

- **One folder per frozen config.** A tool builds the instance, validates it (incomplete: refused),
  freezes it with the hashes of what it reads, and writes `<workspace>/<identity>/`: the frozen
  `config.yaml`, its artifacts, and its `datapackage.json` last. The name and the provenance are in
  the frozen config but not in the identity.
- **The manifest is the "finished" marker.** A finished folder is reused; an unfinished one is
  written again.
- **A tool computes only from manifests and its frozen config.** If it reads state derived from the
  log (labels in effect), it writes that state into its output and hashes it into its config.
- **Views write only under `views/`**, and nothing reads a view's files.

## 6. Inputs, statuses and export *(P6, P7)*

- **A stage declares the artifacts it reads**, each required and checked against its schema. Who
  produced an artifact does not matter.
- **A status annotates; each tool filters.** The input keeps every item. A tool that leaves out
  excluded items says so in its docstring. Statuses of several stages are joined on their key when
  read.
- **Relations between artifacts are declared once** and checked wherever both meet: at launch and
  at export.
- **`export` is the agent's last command.** It builds the artifacts from the output it publishes
  and the decisions in effect, validates schemas and relations, and writes `export/` with its
  manifest. The refusal names items, not rows, and is the agent's feedback. The next stage reads
  `export/` through its own input manifest.

## 7. Agent definitions, skills and hooks

Each role is an agent definition, and each workflow has a skill. Both can declare hooks in their
frontmatter:

| where | restricts tools | hooks run |
|---|---|---|
| agent definition | `tools:` (allowlist), `disallowedTools:` | for every call of the agent, while it runs, also as the main thread (`claude --agent <role>`) |
| skill | `disallowed-tools:` while the skill is active | from the moment the skill is invoked to the end of the session |

- **The role file holds what every turn needs.** Who the agent is, its CLI in literal form, that it
  decides only from command output, how it submits and watches jobs, when it gives `feedback`, and
  the shape of its final message. The skill holds reference the agent reads again (also after a
  compaction): how to read each view.
- **`tools:`** `Bash, Read, Glob, Grep` and the job-watching tool. Add `Write` only for a role that
  writes a file by hand.
- **One `PreToolUse` hook is the gate.** It accepts the agent CLI, the scheduler commands the skill
  uses, and reads; it refuses everything else with exit 2 and a reason that names the command to
  use. It sets `"onFailure": "block"`, and any error in the hook refuses the call (`DES-5`).
- **Hooks run the snapshot's code** (`cd "$CLAUDE_PROJECT_DIR"` first), and only in a folder that
  Claude Code trusts; outside one they are skipped with no error, so the pilot checks they fire.
- **Block only what is clearly unwanted and simple to detect.** Leave the rest to log review.

## 8. Feedback and log review

- **`feedback` is one command in every workflow**: `kind` (`missing_view`, `unexpected`,
  `too_verbose`, `problem`, `other`), the `command` it concerns, and `text`. It appends to the
  workspace's `feedback.jsonl`, one point per entry, when the friction happens.
- **Log review** reads the transcripts and feedback of a round: calls and refusals per command,
  commands nobody used, deviations (Bash that is not a workflow command, reads outside the
  workspace and input, refused calls), feedback by kind. A high refusal rate is friction, also
  without feedback.
- **Close the loop.** Triage the review into issues; a change cites the feedback it answers; the
  next review shows whether the friction is gone. A deviation is a signal about the tools first:
  an agent that ran `python -c` usually lacked a view.

## 9. Orchestrator

The orchestrator (a human or a session) launches agents and reads their exports. It does not
decide for an agent, call its commands, or do its work: without the hooks and the log, that work
cannot be reviewed. One agent per stage, or per independent unit of work in a stage.

## Signs that a design is going off track

| Sign | Look instead at |
|---|---|
| Code that tracks progress or tells the agent what to do next | the agent's agency: commands it chooses, refusals when a call is invalid |
| Code that chooses a parameter, a channel or an option for the agent | a tunable field the agent sets, with a view for the evidence |
| A default, a fallback, an "if absent, treat as ..." | a required artifact; an invariant refused at the boundary |
| A branch for one stage, one caller or one variant | the flaw that needs it (`DES-2`), or a discriminated union |
| Introspection, a marker type, a registry of rules, a second model of the same data | the library's mechanism (`DES-3`) and the one schema |
| A cache, a lock, a scratch folder, parallel calls before the workflow runs end to end | the serial version (`DES-4`) |
| A check that lets an action through when it fails | refuse (`DES-5`) |
| A step a human finds awkward to run or to read | the same awkwardness for the agent: fix the command |
| A note cites numbers no view printed | add the view, or decide without it and give `feedback` |
| Every row of every table printed | overview, then `--ids`, then flags that add columns |
| Commands documented with shell variables and chains | one literal invocation per call |
| A review fix that adds code, or a spot fixed again in a later round | a fix that deletes; a design question for the user (`DES-7`) |
| A design that feels hacky | the design: stop and look again |

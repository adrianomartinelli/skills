---
name: agentic-system-design
description: How to design a system that agents operate and humans use the same way - tools built around contracts, views built around artifacts, an append-only decision log, an export, and the build order (contracts, an end-to-end dummy, then the real logic). Use it before you build or change anything agents operate - a tool, a view, a config type, an artifact schema, an item command. Triggers - "add a tool/view for agents", "agent workflow", "design a workflow agents run".
---

# agentic-system-design

The principles for a system that agents operate: what an agent sees, calls and may change, and how
its work is recorded and handed on. The project's `AGENTS.md` sets the rules every design follows
(`DES-1` to `DES-7`) and the preferred tools. The `contract-design` skill governs the contracts
themselves. How to read the views of one workflow is that workflow's skill.

`patterns.md` next to this file holds a runnable code example for each section marked *(P1)* to
*(P7)*. Read the pattern before you build the part.

## Terms

- **Contract**: what crosses a boundary between programs, written down so both sides can check it:
  a config type, an artifact schema, a relation between artifacts, a command's request model.
- **Workspace**: the one folder a session works in, on one commit. Every command writes into it,
  and only there.
- **Command**: one subcommand of the agent CLI, the one program an agent calls. Its kinds are
  below.
- **Config type, config instance**: a config type is a contract for a tool's parameters. An
  instance is a named copy of it that the agent creates and sets.
- **Tool**: a command that computes (`segment`, `cluster`). It runs one config instance and writes
  a tool output. Not a harness tool such as `Bash` or `Read`.
- **Artifact**: data with a schema (a table, an image stack) that a tool writes and that tools and
  `export` read.
- **Manifest**: a `datapackage.json` in the Frictionless Data Package format. It lists the
  artifacts of its own folder, each with a `name`, a `path` relative to the manifest, and a
  `hash` (`sha256:<hex>`). It is the only way a tool finds an artifact.
- **Tool output**: the folder `<workspace>/<identity>/` that one tool call writes: the frozen
  config, the artifacts and the manifest. The identity is the hash of the frozen config.
- **View**: a command that reads artifacts and prints numbers (`get_*`) or draws a figure
  (`draw_*`). It changes nothing.
- **Item**: one row of an artifact that the agent decides on (a cluster, a channel), named by
  `--ids`.
- **Decision log**: `decisions.yaml`, append-only, one entry per accepted call.
- **Brief**: the text a human gives the agent: targets, hints, what to choose. No code reads it.
- **Export**: the validated artifacts and their manifest in `export/`, the result of a workspace
  that other workspaces read.

## Principles

- **Built for agents and humans equally.** A human runs the same commands in the same workspace,
  reads the same outputs, and decides through the same calls. `--help` shows each command's
  contract; folder names, the decision log and the configs are readable; figures are PNG files; a
  refusal says what to change. A step that is awkward for a human is awkward for an agent too, and
  the fix is the same.
- **Agents have agency.** The agent chooses its config instances, the values it sets, which tools
  it runs and in which order, which views it reads, and when it exports. The code validates each
  call and refuses an invalid one. It never chooses for the agent (no automatic choice of a
  parameter or a channel) and never tells it what to do next. The state of the work is the
  decision log and the finished tool outputs; no code tracks progress.
- **Every number a decision rests on was printed by a view**, and every figure was drawn by one.
  When no view shows the evidence a decision needs, the agent says so with `feedback` and decides
  with what exists, or stops. It never computes the evidence itself: a decision built on ad-hoc
  analysis looks exactly like a good one, and nobody can check or repeat it.
- **Tools are built around contracts.** A tool is its config type, the schemas of the artifacts it
  reads, and the schemas of the artifacts it writes. Everything it assumes is in those contracts;
  every other assumption stays inside the tool.
- **Tools are loosely coupled: they share data, never knowledge.** A tool knows the contracts of
  what it reads, and nothing about the tool that wrote it, the workspace it lives in, or how
  another tool lays out its folder. Each input is a named field of its config that holds the path
  of a manifest, and the field's name is the input's name everywhere it appears. The tool finds
  the artifact in that manifest by name and validates it with its schema. So any manifest that
  lists a valid artifact works: a tool output in this workspace, the export of another workspace,
  a table a human built.
- **Views are built around artifacts.** A view reads artifacts and shows them to the agent and the
  human. An artifact is data; a view's output is a picture of data. A tool output's manifest lists
  artifacts only. No tool, no export and no other view reads a view's files, and they can be
  deleted and drawn again at any time. A number that a tool needs is an artifact: a tool computes
  it, not a view.

## A minimal example

Two tools, `segment` and `cluster`, in one workspace. Each line is one literal call:

```
init seg1 segmentation
set_config seg1 '{image: /data/run7/export/datapackage.json, nuclear: [DNA1]}' --reason "brief: DNA1 is the nuclear stain"
segment seg1                -> 3f9a/  config.yaml  cells.parquet  datapackage.json
get_cells seg1              prints the cell count per image
init cl1 clustering
set_config cl1 '{cells: 3f9a/datapackage.json, k: 12}' --reason "get_cells: 2 to 5 thousand cells per image"
cluster cl1                 -> 8c21/  config.yaml  clusters.parquet  assignments.parquet  datapackage.json
get_clusters cl1            prints one row per cluster: size, median of each marker
draw_clusters cl1           -> views/8c21/heatmap.png
set_cluster cl1 --ids 3 7 '{label: T cell}' --reason "get_clusters: CD3 is the highest median in 3 and 7"
export cl1                  -> export/  clusters.parquet (labels applied)  datapackage.json
```

```python
class ClusteringTunable(BaseModel):  # part of the cluster tool's contract
    model_config = ConfigDict(extra="forbid")
    cells: Path   # a manifest that lists a `cells` artifact; who wrote it does not matter
    k: int        # no default: the agent chooses
```

- `set_config` logs `cells` as an absolute path, and every entry records the commit.
- `cluster` reads `3f9a/datapackage.json` exactly as it would read the export of another
  workspace: it finds `cells` in the manifest and validates it with the `Cells` schema. It never
  knows that `segment` exists. `segment` reads its image the same way from another workspace.
- `cells.parquet`, `clusters.parquet` and `assignments.parquet` are artifacts. The printed rows
  and `heatmap.png` are views: the agent and the human both read them, and nothing else does.
- `decisions.yaml` holds one entry for every call above except the views. The reasons cite what
  the views printed.

## Build order: contracts, a dummy end to end, then the real logic

Follow `DES-6`. Each step is done before the next one starts.

1. **Spec.** For each decision the agent makes: the config field or item command that records it,
   and the view that shows its evidence. A decision without both is not designed yet. For each
   fixed value: why it is fixed.
2. **Contracts.** Config types, artifact schemas, relations between artifacts, the commands, and a
   worked example like the one above: the calls, the log entries, the files, the refusals. Review
   until they agree.
3. **Dummies, end to end.** Every tool with its real contracts and no logic: it writes small,
   schema-valid artifacts. The worked example runs through the real CLI, as a test. This prototype
   exists to find the problems of the design while they are cheap: a decision without a view, a
   tool that needs to know another tool, a step that is awkward to run or to read. Fix each one in
   the contracts.
4. **Real logic**, one dummy at a time. The worked-example test stays green.
5. **The agent's role and skill**, then one pilot agent, then feedback and the changes it shows.

## Commands

| kind | does | writes |
|---|---|---|
| `init` | names a config instance of a type | a log entry |
| `set_config` | patches an instance's tunable fields, with a reason | a log entry |
| tool (`segment`, `cluster`) | runs one instance | a tool output, a log entry |
| view (`get_*`, `draw_*`) | prints numbers, draws a figure | figures under `views/` |
| item command (`set_<noun>`, `annotate`) | sets values of named items, with a reason | a log entry |
| `export` | validates and publishes | `export/`, a log entry |
| `feedback` | reports friction | `feedback.jsonl` |

- **Typed and strict.** `--help` shows the request model. An unknown flag or key is an error. Each
  view is its own subcommand with its own flags.
- **Refusals raise.** The last line says what is wrong and what to change. A refused call changes
  nothing. A missing value is not a refusal: the call is accepted and reports `incomplete: [...]`.
- **Small by default, depth on request.** An overview with one row per item and the columns that
  settle most cases; detail for named items (`--ids`); flags that add columns. One row cap for
  every view, announced with how many rows it dropped and the flag that shows them.
- **One name per concept.** A flag has one name and one type in every command.
- **Reproducible evidence.** A view prints the same output for the same artifacts, arguments and
  commit.
- **Literal invocations.** Document every command as one full literal call, without shell
  variables, loops or chains.
- **Long work runs as a job.** The agent submits a tool to the scheduler itself and watches its own
  jobs. The tool's log entry is appended when the call starts, so a failed job stays visible.
- **Grow from use.** Add a command when feedback shows the need. Delete a command nobody uses.

## Configs *(P1, P2)*

- **A config type is a fixed model and a tunable model**, both `extra="forbid"`, combined flat into
  the tool's config. A fixed value is the fixed model's default, in the code: changing it is a
  commit. The tunable model holds what the agent chooses; a field without a default must be set.
- **Patches merge per key** in log order, then the tunable model validates the result. A field that
  names items of an input (channels, targets) is checked by its own validator. Variants are a
  discriminated-union field (`contract-design`).
- **Every parameter has an owner.** Fixed, with a comment that says why, or tunable, with a view
  that shows the evidence for choosing it.
- **Once a tool used an instance, it is frozen.** Another choice is another instance.
- **Input paths are absolute.** `set_config` resolves each input field to an absolute path before
  it logs the patch, so no path depends on the current directory. Only the paths inside a manifest
  are relative, to the manifest.

## Decision log *(P3, P5)*

- **One `decisions.yaml` per workspace, append-only.** The command writes each entry: the command,
  the instance, the patch, the reason, its inputs by name (`input: {cells: <manifest>}`), the
  manifest it wrote (`output`), `commit`, `at`, and `by` (the session id, or `human`). A refused
  call appends nothing. Nobody edits the file by hand; a hook refuses edits.
- **Reasons cite evidence in words**: the numbers the call rests on and the view they came from.
- **A later entry is the revision**, and both entries stay.
- **Item decisions are patches validated by the artifact's own schema.** A call validates the rows
  it names; `export` validates the whole table with the same schema.
- **A call applies to the tool output it read**, never to another one.
- **Defaults.** One `--default` call covers the items that have no value yet; its entry lists them.

## Tool outputs and artifacts *(P4, P6, P7)*

- **One folder per frozen config.** A tool validates the instance, freezes it with the commit and
  the hash of each artifact it reads (from that artifact's manifest), and writes the frozen
  `config.yaml`, its artifacts, and its manifest last, which records the commit too.
- **One workspace, one commit.** The commit is part of the identity, so new code never reuses an
  old output. Every command refuses a workspace of another commit and a dirty tree. New code means
  a new workspace that reads the old one's export; an old decision log is never replayed by new
  code.
- **The manifest is the "finished" marker.** A finished folder is reused; an unfinished one is
  written again.
- **A tool computes only from manifests and its frozen config.** If it reads state from the
  decision log (labels in effect), it writes that state into its output and into its frozen config.
- **A status annotates; each tool filters.** An artifact keeps every item. A tool that leaves out
  excluded items says so in its docstring.
- **Relations between artifacts are declared once** and checked wherever both meet: in a tool that
  reads both, and at export.
- **`export` is the agent's last command.** It builds the artifacts from the tool output it
  publishes and the decisions in effect, validates schemas and relations, and writes `export/` with
  its manifest. Its refusal names items, not rows.

## Views

- **One call serves the agent and the human.** The agent decides from the printed numbers; the same
  call draws the figure a human would read the same data from (a histogram where the agent reads
  quantiles). Every number a decision rests on is printed, never only drawn.
- **When the image is the data** (cell crops, an overlay), the image is the one output both read.
- **One question per figure**, under 2 MP and 2000 px on the long edge, so an agent can read it.
  Split a figure into files when it grows with the data.
- **Views write only under `views/`.**

## Agents and feedback

- **The agent's role file holds what every turn needs**: who it is, its CLI in literal form, that
  it decides only from command output, when it gives `feedback`, and the shape of its final
  message. The workflow's skill holds what it reads again: how to read each view.
- **Sessions run pinned code** from a snapshot (the `snapshot` skill).
- **`feedback` is one command in every workflow**: `kind` (`missing_view`, `unexpected`,
  `too_verbose`, `problem`, `other`), the `command` it concerns, and `text`. One point per entry,
  when the friction happens.
- **Review the transcripts and the feedback** after a set of sessions: calls and refusals per
  command, commands nobody used, Bash that is not a workflow command, feedback by kind. A deviation
  is a signal about the commands first: an agent that ran `python -c` usually lacked a view.
  Triage into issues; a change cites the feedback it answers.

## Signs that a design is going off track

| Sign | Look instead at |
|---|---|
| A tool that builds a path to another tool's files, globs for the latest output, reads another tool's config, or branches on who wrote its input | loose coupling: a manifest path in the config, the artifact found by name and checked by its schema |
| A tool or an export that reads a view's figure or printed table | the number is an artifact: a tool computes it |
| Code that tracks progress or tells the agent what to do next | the agent's agency: commands it chooses, refusals when a call is invalid |
| Code that chooses a parameter, a channel or an option for the agent | a tunable field the agent sets, with a view for the evidence |
| A default, a fallback, an "if absent, treat as ..." | a required artifact; an invariant refused at the boundary |
| A branch for one caller or one variant | the flaw that needs it (`DES-2`), or a discriminated union |
| Introspection, a marker type, a registry of rules, a second model of the same data | the library's mechanism (`DES-3`) and the one schema |
| A cache, a lock, a scratch folder, parallel calls before the dummy runs end to end | the serial version (`DES-4`) |
| Real logic written before the dummy ran end to end | the contracts and the dummy first |
| A check that lets an action through when it fails | refuse (`DES-5`) |
| A step a human finds awkward to run or to read | the same awkwardness for the agent: fix the command |
| A note cites numbers no view printed | add the view, or decide without it and give `feedback` |
| A review fix that adds code, or a spot fixed again later | a fix that deletes; a design question for the user (`DES-7`) |

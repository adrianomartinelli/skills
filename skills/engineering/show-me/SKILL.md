---
name: show-me
description: "Explain how part of a codebase is implemented, visually: its contract (the API, arguments and config it consumes, the return value and artifacts it produces), how it interacts with the rest of the system, and its edge cases, as an interactive HTML page. Use when the user asks how a module, class, function, script or pipeline stage works or is implemented, what it takes or produces, or says \"show me\", \"walk me through\", or \"explain this component\"."
metadata:
  credits:
    skill: show-me
    author: Dex Horthy
    organisation: Humanlayer
    url: "https://github.com/humanlayer/skills/blob/main/plugins/show-me/skills/show-me/SKILL.md"
---

Explain one component of the codebase so the user can hold its **contract** in their head: what it consumes, what it produces, and how it gets from one to the other. Skip the preamble. Pick the smallest view that makes each point clear.

## 1. Scope

Name the component in one line: the entry point (a function, class, script or stage) and the question the user asked about it. A narrow question ("why does X skip empty ROIs?") gets an inline answer: one or two visuals from [the menu](#visual-menu) in the reply, no page, and you are done. A question about how a component works or what it takes and produces gets the page: go on to step 2.

Done when the entry point is a file and symbol you can open.

## 2. Trace the contract

Read the entry point and follow the calls until every input and every output ends at the code that parses or writes it. When the trace spans more than about five files, dispatch an Explore subagent with a fresh context window for the reading and keep only its file:line findings.

Collect, each with its `file:line`:

- **Interface**: the signature, CLI arguments, and the config model with each field's type, default and meaning. Mark the fields that change what is computed apart from execution-only ones (workers, log interval).
- **Inputs**: what it reads (files, tables, other components' artifacts, `Settings`, environment) and who produces them.
- **Outputs**: the return value and every artifact it writes, with the path layout (from the paths class where one exists) and the structure of each file (columns and dtypes, keys, array shapes).
- **Interactions**: its callers, the components it calls, and its side effects (disk, network, scheduler, global state).
- **Edge cases and limitations**: what raises, what is skipped, filtered or defaulted silently, what is assumed and never checked, and where it stops scaling.

Done when each input and each output has a `file:line` for the code that reads or writes it.

## 3. Ground it in real examples

Show real values, not invented ones:

- **Config**: quote a committed config file that the component consumes (for example under `configs/`). With no committed file, build the example from the model's defaults and label it `defaults`.
- **Artifacts**: open one existing artifact read-only and show its real structure: the schema and a few rows of a table, the top-level keys of a JSON or YAML file, the shapes and dtypes of an array. Read only the header or a small sample of a large file. With no artifact on disk, derive the structure from the writer code and label it `from code`.

Done when every example on the page is labelled with its source: a file path, `defaults`, or `from code`.

## 4. Write the page

Write one self-contained HTML file outside the repo: the harness scratchpad if it has one, otherwise `$TMPDIR` (fall back to `/tmp`), as `show-me-<component>-<timestamp>.html`. [HTML.md](HTML.md) holds the scaffold, the sections and the interactive patterns. Every section is short; the visuals carry the explanation, and the prose is a sentence or two beside each visual.

Keep only the arguments, fields, calls and files that bear on the user's question. A config with forty fields shows the handful that drive the logic, and links the model's `file:line` for the rest.

Done when every claim on the page that the user could check has a `file:line`, and every section from HTML.md that applies is filled.

## 5. Present

Open the page for the user (`xdg-open` on Linux, `open` on macOS, `start` on Windows), or publish it with the harness's artifact or preview tool when it has one. Give the absolute path or link, and a reply of a few lines: the component's job in one sentence and its contract as a one-line sketch (`config + inputs -> component -> return + artifacts`).

## Visual menu

Use these inline in a reply, and as the building blocks of the page. Place each visual next to the short text it supports. Use one, sometimes several, rarely all.

- **Contract**: what goes in and what comes out.

```text
SegmentConfig (configs/segment/*.yaml) ─┐
ROI images (image_qc export)        ────┼─> run_segment() ─┬─> masks/<roi>.tiff   uint16 label image
Settings.outputs_dir                ────┘                  └─> cells.parquet      one row per cell
```

- **Pseudocode** for logic or an algorithm:

```text
for roi in included_rois
  if roi has no nuclear channel
    skip and log
  mask = cellpose(roi, diameter)
  write mask
```

- **Call tree** for runtime control flow:

```text
main (scripts/segment.py)
  run_segment
    load_rois
    segment_roi
      cellpose.eval
    measure_cells
```

- **File tree** for an artifact layout or file responsibilities:

```text
outputs/<identity_hash>/
├── config.yaml        # resolved config and provenance
├── masks/             # one label image per ROI
└── cells.parquet      # per-cell measurements
```

- **Mermaid** for interaction or data flow between components (`sequenceDiagram`, `flowchart`).
- **Diff** when the point is what a change does to a shape that already exists (a call tree, a file tree, a config).
- **Whole block** when most of it matters, or the user needs a copyable shape: the config model class, a dataclass, a table schema.

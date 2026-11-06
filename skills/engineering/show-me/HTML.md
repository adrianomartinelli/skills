# The show-me page

One self-contained HTML page. It reads from **whole to detail**: the overview is the only open section, and every other section is a fold the reader opens from a link in the overview. When the harness publishes pages with its own artifact or preview tool, that tool's page contract wins over everything below (its skeleton, theme tokens, allowed CDNs, built-in Mermaid); keep the structure and the patterns, and drop what the contract forbids.

## Structure

```text
header            component, entry point file:line, the commit it was read at, its job in one sentence
overview          always open: the contract diagram, the lifecycle (if any), the drill-down index
[expand all / collapse all]
<details> × N     one per section below, closed; the summary is the heading plus a one-line description
```

The overview answers "what is this and how does it fit" without opening anything. Every box of the contract diagram and every entry of the drill-down index is an `<a href="#section">`; a click opens that fold (and any fold around it) and scrolls to it.

## Sections

Drop a section that has nothing to say for this component (a pure function writes no artifacts); never pad one.

| Section | Holds |
| --- | --- |
| Overview | The contract diagram: inputs left, the component middle, outputs right. The lifecycle, when the component has states or steps (an agent workflow, a state machine, a multi-stage run): a Mermaid `stateDiagram` of what moves it on. The drill-down index: one link per section with a one-line description. |
| Config and arguments | The signature or CLI, the config model as a table (field, type, default, meaning; computed vs execution-only), the real config file in a fold. |
| Inputs | What it reads and who produces it, each with its real structure in a fold. |
| Execution | How it interacts with the system: callers, callees, processes, side effects, as one Mermaid sequence diagram, then the core code. |
| The core unit | The innermost function that does the work, as real code with comments, then a table of what it writes and what a retry does. |
| Outputs | The return value, the artifact layout as a file tree, one fold per artifact with its real structure (schema plus a few rows, keys, shapes). |
| Edge cases and limitations | One row per case: a label (`raises`, `defaults`, `skips`, `limit`), what happens, `file:line`. Then "Read next": three to five `file:line` locations with a one-line reason. |
| Follow-up questions | When the user asks about the page, answer in the section the question belongs to, as a marked answer block, republish the same page, and mark the answered sections in the drill-down index. |

## Patterns

**Fold.** Sections are `<details class="sec">`; inside them, a real file, a long schema or a secondary function is a nested `<details>` whose summary already says what it holds (`cells.parquet: 17,341 cells × 51 columns`) and carries its source label (`configs/...`, `defaults`, `from code`).

**Code.** Every code excerpt, config file, table sample and JSON is a `<pre><code class="language-…">` block with syntax highlighting: highlight.js 11.9.0 from cdnjs (`highlight.min.js`, which covers python, yaml, json, bash) and a few `.hljs-*` colour rules of your own. Show the real code, trimmed to the lines that matter, with the `file:line` of the function in a comment on its first line and a comment on each line that needs one. Pseudocode only where the real code is spread over many functions.

**Answer block.** A question the user asked gets a block with the question as its first line, the answer in plain prose, then the code that proves it. Questions about *why* code is split or arranged a certain way are answered from the constraint that forces it (an import that cannot happen, a version pin, a scheduler limit), with the `file:line` or config line that states it.

**Edge-case list.** One row per case, its label as a coloured badge (`raises` red, `defaults` and `skips` amber, `limit` grey), so a silent default stands out from a loud error.

**Script.** The only script: highlight the code, open the fold an anchor link targets (and its ancestors), expand all and collapse all, and open the fold named in `location.hash` on load.

```js
function openTarget(id) {
  const el = document.getElementById(id);
  for (let n = el; n; n = n.parentElement) if (n.tagName === "DETAILS") n.open = true;
  el?.scrollIntoView({ block: "start" });
}
```

## Style

- Plain and schematic, generous whitespace, one accent colour; red and amber only for edge-case badges. Take the accent from the subject where it has a convention (a figure's colour code, a domain's standard palette).
- Monospace for every identifier, path and value. Use the project's own names from `GLOSSARY.md` where it has one.
- `file:line` references in small grey monospace after the text they support.
- No horizontal page scroll at phone width: code blocks and tables scroll inside their own box.

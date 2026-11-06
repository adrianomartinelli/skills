## What it does

`show-me` explains how one component of a codebase is implemented: a function, a class, a script or a pipeline stage. It traces the component's **contract** (the arguments, config and inputs it consumes, the return value and artifacts it produces), how it interacts with the rest of the system, and its edge cases and limitations. It then renders that as an interactive HTML page.

Every example on the page is real. The skill quotes a committed config file instead of an invented one, opens an existing artifact read-only to show its actual schema and a few rows, and labels anything it had to derive from code as `from code`. Every claim you could check carries a `file:line`.

## When to reach for it

Type `/show-me`, or the [agent](https://www.aihero.dev/ai-coding-dictionary/agent) reaches for it automatically when you ask how something works or is implemented.

| Your situation | Reach for |
| --- | --- |
| You need to understand what a component takes, does and produces | `show-me` |
| A narrow question about one behaviour ("why does it skip this case?") | `show-me` answers inline with one small visual, no page |
| You want to change a module's shape, not understand it | [codebase-design](https://aihero.dev/skills-codebase-design) |
| The question is about outside docs or an API, not this code | [research](https://aihero.dev/skills-research) |

## The contract view

The page reads from whole to detail. Only the overview is open: one diagram with inputs on the left, the component in the middle and outputs on the right, a lifecycle diagram when the component moves through states or steps, and a link to every section. Each box and link opens a collapsed section with the real thing: the config model as a table plus the committed config file, how a run executes, the innermost function as highlighted real code, each artifact's layout and structure, and a list of edge cases labelled `raises`, `skips`, `defaults` or `limit`.

Ask a follow-up question and the answer goes into the same page, in the section it belongs to, and the page is republished. The page grows into the record of what you asked about the component.

## It's working if

- You can say what the component consumes and produces from the contract diagram alone.
- The config and artifact examples carry a source label, and the labelled files exist.
- The edge-case list names silent defaults and skips, not only the errors.
- The reply in the chat is a few lines and a link, not the explanation itself.
- You understand the component from the overview alone, and open a section only for the detail you need.

## Where it fits

A reach-for-it-anytime standalone, most useful before you change a component you did not write. [codebase-design](https://aihero.dev/skills-codebase-design) is the neighbour for redesigning what `show-me` explained, and [pr](https://aihero.dev/skills-pr) uses the same menu of visuals for a diff. [ask-matt](https://aihero.dev/skills-ask-matt) routes across the whole set.

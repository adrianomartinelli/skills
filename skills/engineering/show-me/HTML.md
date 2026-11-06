# The show-me page

One self-contained HTML file. Tailwind and Mermaid come from CDNs at pinned versions; everything else is inline. Interactivity is native HTML: `<details>` to fold a config or a schema open, and anchor links from the contract diagram to the section that explains each box. The page reads top to bottom with every fold closed.

## Scaffold

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{{component}}</title>
    <script src="https://cdn.tailwindcss.com/3.4.16"></script>
    <script type="module">
      import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.esm.min.mjs";
      mermaid.initialize({ startOnLoad: true, theme: "neutral", securityLevel: "loose" });
    </script>
  </head>
  <body class="bg-stone-50 text-slate-900">
    <main class="max-w-5xl mx-auto px-4 py-10 space-y-10">
      <header>...</header>
      <section id="contract">...</section>
      <section id="config">...</section>
      <section id="outputs">...</section>
      <section id="flow">...</section>
      <section id="logic">...</section>
      <section id="edges">...</section>
      <section id="read-next">...</section>
    </main>
  </body>
</html>
```

## Sections

In this order. Drop a section that has nothing to say for this component (a pure function writes no artifacts); never pad one.

| Section | Holds |
| --- | --- |
| Header | Component name, entry point `file:line`, the commit it was read at, and its job in one sentence. |
| Contract | The centrepiece: inputs on the left, the component in the middle, outputs on the right. Each box links to its section below. |
| Config and arguments | The signature or CLI, then the config model as a table (field, type, default, meaning; computed vs execution-only), then the real config file in a fold. |
| Outputs | The return value, the artifact layout as a file tree, and one fold per artifact with its real structure (schema plus a few rows, keys, shapes). |
| Flow | How it interacts with the system: callers, callees, side effects, as one Mermaid sequence or flowchart. |
| Core logic | Pseudocode or a call tree of the steps that matter, each step with `file:line`. |
| Edge cases and limitations | A list: the condition, what happens, `file:line`. Label each `raises`, `skips`, `defaults` or `limit`. |
| Read next | The three to five `file:line` locations to open first, each with a one-line reason. |

## Patterns

**Contract diagram.** Three columns of boxes in a CSS grid, the component box thick and dark, the input and output boxes light. Each box is an `<a href="#...">` to its section, with the source label (`configs/...`, `defaults`, `from code`) in small type underneath. Stack the columns on narrow screens.

```html
<div class="grid md:grid-cols-[1fr_auto_1fr] gap-4 items-center">
  <div class="space-y-2">
    <a href="#config" class="block rounded border bg-white p-3 hover:border-indigo-500">
      <div class="text-xs uppercase tracking-wider text-slate-500">config</div>
      <div class="font-mono text-sm">SegmentConfig</div>
      <div class="text-xs text-slate-400">configs/segment/pilot.yaml</div>
    </a>
  </div>
  <div class="rounded-lg bg-slate-900 text-white p-4 font-mono">run_segment()</div>
  <div class="space-y-2">...</div>
</div>
```

**Fold.** A real file or a long schema goes behind `<details>`, with a one-line summary that already says what it holds:

```html
<details class="rounded border bg-white">
  <summary class="cursor-pointer p-3 font-mono text-sm">cells.parquet: 14 columns, one row per cell</summary>
  <pre class="overflow-x-auto p-3 text-xs">...</pre>
</details>
```

**Field table.** Highlight the fields the logic branches on; grey out the execution-only ones.

**Edge-case list.** One row per case, its label as a coloured badge (`raises` red, `skips` and `defaults` amber, `limit` slate), so a silent default stands out from a loud error.

## Style

- Plain, schematic, generous whitespace. One accent colour (indigo), red and amber only for edge-case badges.
- Monospace for every identifier, path and value. Use the project's own names from `GLOSSARY.md` where it has one.
- `file:line` references in small grey monospace after the text they support.
- No horizontal page scroll at phone width: code blocks scroll inside their own box.

---
name: fallback-review
description: Review code for special cases that a sound design would not need, which are fallbacks and defaults for gaps, backward-compatibility shims, branches for one input or caller, and features nobody asked for. Reports each with the invariant or deletion that removes it. Use for "fallback review", "check for shims", "is this over-special-cased", or after implementing a change, before code-review.
---

# Fallback review

A special case is code that exists for one situation the main path does not handle. Each one is a question: **can this case occur, and did anyone ask for it to be handled?** If the case cannot occur, the code is dead weight that hides the real contract. If it can occur but the design forces a branch for it, the design is the problem. Report only; change no files.

## 1. Scope

- Target: the diff against the merge-base with `main` (`git diff $(git merge-base HEAD main)`), unless the user names a commit, branch, PR, or path.
- The request: read the issue, spec, or user message the change answers. "Nobody asked for it" is judged against this text. If there is none, say so in the report and judge against the callers alone.
- Standards: if the repo has `CODING_STANDARDS.md` or `AGENTS.md` rules on legacy support or fallbacks, cite their IDs in findings.

## 2. Review

Start one subagent with a fresh context window. Give it the diff, the request text, the four categories below, and the output format. A fresh reviewer is not anchored on the reasons the author gave for each branch.

1. **Fallback.** Code that substitutes something when an input is missing or wrong: a default argument whose `None` path invents a value, `.get(key, default)`, `x or default`, NaN or zero fill, `except: pass` or `except: continue`, "if the artifact is absent use the parameter", partial-coverage handling.
2. **Shim.** Code that keeps an older shape working: reading an old file layout or config key, a renamed function or flag kept as an alias, a version check, a `legacy` or `compat` branch, a re-export kept for old imports.
3. **Special-case branch.** A condition on one name, dataset, cohort, type, or caller (`if name == "X"`, an `isinstance` ladder, a flag one caller sets). It signals that the data model or interface does not fit the cases it serves.
4. **Unrequested feature.** An option, mode, parameter, config key, or code path that the request did not ask for and no caller uses.

For each candidate the subagent greps the callers and, where cheap, the data, to answer: **can the case occur?** It returns, per finding:

```
<file>:<line>  <category>
case:     <the situation the code handles>
occurs:   yes | no | unknown, with the evidence (callers, data, grep result)
remedy:   delete | state the invariant and refuse at <boundary> | fix the model so the branch disappears
```

## 3. Verify and report

Check each finding yourself before you report it. Drop it if:

- it refuses bad input at a trust boundary (user input, external data, an API response). A check that raises is the remedy, not the problem.
- it prevents data loss or handles a failure the request asked to handle.
- the request asked for the case explicitly.

Report the surviving findings ranked by how much code their remedy removes, then one line per dropped finding with the reason. For each `occurs: unknown`, write the question the user must answer (for example "Can a record lack a field the schema lists?"). The review is complete when every special case in the diff is either a finding or named as justified.

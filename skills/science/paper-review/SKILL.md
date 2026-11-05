---
name: paper-review
description: Multi-agent review workflow for a paper draft (LaTeX or otherwise) -- three parallel domain-specific reviewer personas, plus a mandatory verify-before-apply discipline. Use for "review this draft", "reviewer comments", manuscript feedback.
---

# paper-review

Runs a full-paper review as three parallel, read-only subagents with different reviewer
personas, then reconciles their findings against ground truth before touching the draft. The
personas below are the defaults for an ML-on-domain-data paper; swap them for whatever three
angles actually matter for the paper at hand (e.g. a systems paper might want
performance-engineering, security, and editor instead).

## The three-reviewer split

1. **Technical/methods expert** (e.g. computer vision, ML, systems) -- architecture and method
   correctness, experimental design validity (splits, checkpoint/hyperparameter selection,
   baselines), statistical rigor of any claim involving folds/seeds/repeats, notation
   consistency, whether each figure/table backs the specific claim citing it.
2. **Domain expert** (e.g. biology, clinical, the paper's actual subject-matter field) --
   domain-specific correctness of terminology and task definitions, dataset/cohort description
   accuracy, whether baselines and comparator methods are domain-appropriate, whether
   biological/domain-mechanism interpretation in the discussion is adequately hedged.
3. **Scientific editor** -- figure/table referencing integrity (every label cited, every ref
   resolves, figure numbers appear in the same order they're first cited), cross-section
   consistency (the same number/claim phrased compatibly everywhere it appears), appendix
   hygiene (no reasoning that belongs in the discussion, no restated content that adds nothing),
   writing quality, abstract-body consistency, and workshop/venue fit if applicable.

Launch all three as a single Agent tool call with three invokes in one message (they run in
parallel, in the background) -- not sequentially. Use a fresh, non-fork agent for each: they
should read the paper cold, not inherit the orchestrating conversation's framing or assumptions.

## Prompting each reviewer

Each prompt must be self-contained (the agent has no memory of this conversation) and must say,
explicitly:

- What the paper is about (one paragraph), and where the file is.
- **This is a read-only review. Do not edit the file. Report findings only.**
- The specific focus list for that persona (see above), tailored to this paper's actual content
  -- name the specific sections/tables/figures worth checking, not just generic categories.
- Report format: file location (line/section), one-sentence issue description, why it matters,
  and only report things that are actually wrong -- don't force a finding in every category.
- For the editor persona specifically: ask for an *exhaustive* pass on label/ref integrity (every
  `\label` cited or justified as intentionally uncited; every `\ref` resolves; figure numbering
  order matches first-citation order), not a spot check -- this is mechanically checkable and
  cheap to do completely.

## Verify every finding before acting on it

Subagent findings are claims, not facts -- treat a "critical" severity tag with the same
skepticism as a "minor" one. Before applying or even reporting a finding to the user as valid,
check it against the actual source of truth:

- A numeric claim ("X doesn't beat Y") gets checked against the actual table/data, not accepted
  on the reviewer's say-so. Concrete example hit in practice: a CV-reviewer agent flagged as
  **Severity 1 Critical** that a paper's claim ("model A beats all four baseline configs on every
  endpoint") was false, citing two specific numbers it claimed contradicted the claim. Checking
  those exact two numbers against the paper's own results table showed the cited baseline value
  was *lower* than model A's score in both cases -- the claim was correct, and the reviewer's
  arithmetic was wrong. Reported as a real issue, it would have driven an unnecessary rewrite of
  a defensible sentence.
- A methodology claim ("this number looks like it was picked using held-out test performance")
  should not be resolved by re-reading the *paper's prose* more carefully -- the paper text
  describes the intended procedure, but the actual selection happened in code. Trace it to the
  source of truth: the script/notebook that produced the reported number and whatever
  intermediate results file it reads from. Confirm the selection logic (e.g. "pick the checkpoint
  with highest *validation* score, then report its *test* score") against what the code actually
  does, not against what the paper says it does -- the two can silently drift apart over a long
  editing session.
- A "figure doesn't support this claim" finding is checked by reading the figure's actual caption
  and, ideally, looking at the rendered image -- not by re-reading the citing sentence again.

Findings that survive this check split into two buckets:

- **Trivial and unambiguous** (a stray typo character, a genuinely uncited figure with no
  main-text mention anywhere, a caption that misdescribes a chart element that's since changed):
  fix directly, then re-run the mechanical checks (see below) and report what was changed.
- **Substantive or ambiguous** (anything touching methodology correctness, anything where the fix
  requires a judgment call about framing or scope, anything requiring code verification before
  the paper text can be trusted either way): report to the user with the concrete evidence and
  what verification is still needed. Do not silently resolve these by picking whichever
  interpretation requires less work.

## Mechanical integrity checks (run after any edit, before every commit)

Cheap enough to run every time, catches an entire class of self-inflicted bugs from incremental
editing (dangling refs, duplicate labels, unbalanced braces after a botched find-replace):

```python
import re
text = open("paper.tex").read()
labels = re.findall(r'\\label\{([^}]+)\}', text)
refs = re.findall(r'\\ref\{([^}]+)\}', text)
print("dup labels:", [l for l in set(labels) if labels.count(l) > 1])
print("dangling refs:", sorted(set(r for r in refs if r not in labels)))
print("braces:", text.count("{"), text.count("}"))
# figure/table begin-end counts should match; every \includegraphics target should exist on disk
```

For figure-numbering-vs-citation-order specifically, extract the first `\ref{fig:X}` for each X
in document order (= reading order) and separately extract figure numbering order from
`\begin{figure}...\label{fig:X}` occurrence order -- they should match at least for the figures
that matter most (the ones a reader hits early).

## Why this is a skill, not project docs

The three-persona split, the read-only-then-reconcile pattern, and above all the
verify-before-acting discipline are identical regardless of what the paper is about -- the same
failure mode (a confident-sounding subagent finding that's simply wrong, or a paper-text
description of a procedure that's drifted from what the code actually does) recurs on any
paper-writing project. Keeping this here means the discipline travels with you instead of being
re-learned per project.

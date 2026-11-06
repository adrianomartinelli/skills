---
name: debrief
description: Debrief the user on work done while they were away, one item per deviation, assumption, decision, problem, unverified claim, outward action, pending job and open question, each with options to accept, reject or file an issue. Use when you start work the user will not watch (to keep the ledger), when an unattended run ends, and when the user returns ("I'm back", "what happened", "debrief").
---

The user was **away** while you worked. You made choices they did not see. A **debrief** puts each one in front of them as one **item** with a short set of answers, so they can confirm, undo or track it in a few taps. This skill decides *what* the items are; how they are shown is the job of the reply mode (`mobile` renders them as cards).

## While working: keep the ledger

Write the ledger in `WORKTREE.md`, under a `## Debrief ledger` heading after the branch log. No `WORKTREE.md` in the repository: use `$TMPDIR/debrief-${CLAUDE_SESSION_ID}.md`. Commit the ledger with the work it describes.

Add one line **at the moment** it happens, never from memory at the end:

```
- <kind> | <one line> | if wrong: <cost> | <evidence: commit, file:line, job ID> | ${CLAUDE_SESSION_ID}
```

`<kind>` is one of the kinds in the table below. "If wrong" names what a "no" from the user costs: the runs to redo, the files to revert, the results that change. Done when every choice the user did not dictate has a line.

## On return: the debrief

1. **Gather.** Read the ledger lines of the session, `git log` of the session, and the current state of everything still pending (`squeue`, `git status`, unpushed branches). Check a fact before you report it.
2. **Sweep for implicit assumptions.** For each, ask if you took it as true without saying so: the reading of the request, the scope, the data or cohort, every default and threshold, the branch and commit, what "done" means. Add each one you find as an `assumption` item.
3. **Rank.** Order by kind as in the table, and inside a kind by the cost of a "no". Fold the low-cost items into one batch item: "Accept these N low-impact items: <list>", answers Accept all · One by one.
4. **Ask.** One item per idea, self-contained, its evidence held back for "More context". Every item also takes a free-text answer.
5. **Act on each answer**, then delete its ledger line. Done when the ledger of the session is empty.

| Kind | Item | Answers |
|---|---|---|
| **deviation** | "You asked for X; I did Y because Z." | Accept (Recommended) · Revert · File issue · More context |
| **unverified** | "Reported done but not checked: X." | Verify now (Recommended) · Accept as is · More context |
| **assumption** | "I took X as true. If wrong: <cost>." | Confirm (Recommended) · Reject · the most likely sharper version · More context |
| **decision** | "I chose X over Y because Z." | Keep (Recommended) · Keep and record an ADR, when the choice is one a later session must not re-open (then the Recommended one) · Use Y · More context |
| **problem** | "Problem: X. Fix: Y. Side effect: Z." A fix that is a workaround says so. | Accept (Recommended) · Revert · File issue (Recommended for a workaround) · More context |
| **outward** | One item listing every action outside the working tree: pushes, deletes, submitted jobs, created issues. | Fine (Recommended) · More context |
| **pending** | "Still running or left open: X." | Check later (Recommended) · Cancel · More context |
| **question** | The open question, worded so your recommendation is the first answer. A problem you did not solve is a question. | your answer (Recommended) · one or two real alternatives · More context |
| **lesson** | "Lesson: X." | Retrospective (Recommended) · Memory · Ignore · More context |

## Answers

- **More context**: show the evidence and the trade-off of that item in a short paragraph, then ask it again.
- **Revert / Reject / Use Y**: do the rework now if it is small; otherwise file it as an issue and give the number.
- **File issue**: create it in the project's tracker (`docs/agents/issue-tracker.md`, else `gh issue create`) and give the number.
- **Keep and record an ADR**: write it with `domain-modeling`.
- **Retrospective**: add it to `docs/retrospective.md`. **Memory**: save it to the agent's memory.
- **Free text**: read it as the answer. If it changes the premise of another item, ask that item again.

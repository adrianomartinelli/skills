## What it does

When you come back to a session that ran without you, the agent puts every choice you did not see in front of you as one item with a few answers. It does not write a summary for you to read and check. Each item is something you confirm, undo, or file as an issue. The agent writes the items down in a **ledger**, `.ledgers/<session-id>.json`, as it works, so the debrief does not depend on what it remembers at the end.

## When to reach for it

Type `/debrief`, or the agent reaches for it automatically when an unattended run ends or when you say you are back. Ask it to debrief other sessions too, and it reads every ledger in `.ledgers/` with open items.

For handing the work to another agent instead of to yourself, use [handoff](https://aihero.dev/skills-handoff).

## The items

| Kind | What you see | What you can answer |
|---|---|---|
| Deviation | You asked for X, it did Y, and why | Accept, revert, file an issue |
| Unverified | Something reported as done but not checked | Verify now, accept as is |
| Assumption | What it took as true, and what a "no" costs | Confirm, reject, sharpen |
| Decision | What it chose over what | Keep, keep and record an ADR, switch |
| Problem | The problem, the fix, the side effect | Accept, revert, file an issue |
| Outward | Pushes, deletes, submitted jobs, created issues | Fine, more context |
| Pending | Jobs still running, branches left open | Check later, cancel |
| Question | What is still open, with a recommendation | The recommendation or an alternative |
| Lesson | Something to remember next time | Retrospective, memory, ignore |

Every item also has **More context**, which shows the evidence (commit, file, job ID), and a free-text answer.

## Common questions

**How is this different from `mobile`?** `mobile` decides how the agent asks (tappable cards on a phone). `debrief` decides what it asks after unattended work. With both on, every item is a card.

**Where does the ledger live?** In `.ledgers/<session-id>.json`, one file per session, gitignored. Your answer is written into each entry, so the file stays as a record.

**Does the agent log when I did not say I was away?** In a project built from project-init, yes: `AGENTS.md` asks every session to log, and the `SessionStart` hook tells it its ledger path.

## It's working if

- Nothing in the code or the issue tracker surprises you a week later.
- Each item says what a "no" would cost.
- After the debrief, every entry in the ledger has an answer.

## Where it fits

A reach-for-it-anytime standalone at the end of unattended work. It renders through [mobile](https://aihero.dev/skills-mobile) on a phone, and files issues and ADRs in the places [domain-modeling](https://aihero.dev/skills-domain-modeling) and the issue tracker define. The map of the whole set is [ask-matt](https://aihero.dev/skills-ask-matt).

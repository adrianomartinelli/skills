---
name: policy
description: Review the current diff (or a PR, branch, or path) against every numbered rule in the "Policy" sections of AGENTS.md and CODING_STANDARDS.md -- config and CLI, paths and artifacts, code structure, runs, process, legacy support, code style. Runs the `policy-review` workflow (one review agent per Policy subsection with a verdict for each rule, one skeptic per violated rule), then reports per rule, applies mechanical fixes, and asks about the rest. Use for "review against AGENTS.md", "policy review", "check scaffolding conventions", or before merging a branch.
---

# policy

Checks a diff against each rule in the "Policy" sections of `AGENTS.md` and `CODING_STANDARDS.md`,
and reports one verdict per rule. It does not look for correctness bugs (use `/code-review`) or
general code quality (use `/simplify`).

Where each part lives:

- The rules and their review groups: the "Policy" section of `AGENTS.md` and of
  `CODING_STANDARDS.md`, in the project. Each subsection is one group.
- In this skill's base directory, next to this file:
  - `groups.py`: turns those subsections into groups, and checks coverage.
  - `examples.md`: example signs of violations, one `<ID>: <example>` line each.
  - `policy-review.js`: the orchestration (agents, schemas, verification).

## Step 1 -- Get the groups

From the project root, run `python3 <skill base directory>/groups.py`. It prints the groups of both
files as JSON. If it exits with an error, a file is missing, or has a rule outside a subsection, an
empty subsection, a duplicate ID, or a gap in the numbering. Show the error to the user and stop: a
review would leave a rule unchecked.

## Step 2 -- Choose the diff

Write one shell command that prints the diff under review:

1. If the user named a PR, a branch, or a path, review that target. Examples: `gh pr diff 12`,
   `git diff main...<branch>`, `git diff main...HEAD -- <path>`.
2. Otherwise use `git diff @{upstream}...HEAD`. If there is no upstream, use `git diff main...HEAD`.
   On `main` with no range, use `git diff HEAD~1`.
3. If the working tree has uncommitted changes, or the range diff is empty, append
   `; git diff HEAD` so that the command also prints the working-tree changes.

Run the command once. If it prints nothing, tell the user that there is nothing to review and stop.

## Step 3 -- Run the workflow

Call the Workflow tool with `scriptPath: "<skill base directory>/policy-review.js"` and
`args: {"diffCmd": "<the command>", "groups": <the JSON from step 1>, "examples":
"<skill base directory>/examples.md"}`. Pass `groups` as a JSON value, not as a string. These
instructions are the user's request to run the workflow. Do not run the reviewers yourself with the
Agent tool: the workflow is the review.

The workflow returns `rules`: one entry for each rule, with a `status` and one line of `evidence`.

## Step 4 -- Report, then apply

Report every rule, grouped by subsection, as a table: rule ID, status, and evidence. Then act on
each status:

- **`violated`**: the skeptic upheld at least one location. For each location:
  - `kind: "mechanical"` and the rule is not a `LEG` rule: apply the fix directly. Example: a
    hand-built path that becomes a `paths.py` lookup.
  - `kind: "judgment"`: do not guess. Report it with the suggested fix, for the user to decide.
  - A `LEG` rule: never delete silently. Artifacts on disk are real, and a migration that deletes them
    needs the user's approval for each path (ART-1, ART-6). State what the code keeps alive and how
    many artifacts or callers depend on it. Ask the user whether it is needed, and propose the migration that
    removes it as the default.
- **`refuted`**: the reviewer claimed a violation and the skeptic refuted every location. Give the
  skeptic's reason in one line.
- **`unverified`** or **`unreviewed`**: an agent did not return, or returned a violation with no
  location. Do not apply anything. Say which rules have no reliable verdict, and offer to run the
  workflow again with `resumeFromRunId`, which reruns only the agents that did not complete.
- **`complies`** and **`not_applicable`**: the table already shows them.

Skip a fix that needs changes far outside the reviewed diff, and say that you skipped it.

Finish with a summary: what you fixed, what waits for a decision, which rules have no reliable
verdict, and what you skipped.

## Changing a rule or a group

- A rule: edit the project's `AGENTS.md` or `CODING_STANDARDS.md`, and follow the "How to read the
  Policy section" conventions in `AGENTS.md`. The rule is reviewed with the subsection that you put
  it in.
- A new group: add a subsection to "Policy" in either file. `groups.py` picks it up.
- Example signs for a rule: add a line `- <ID>: <example>` to this skill's `examples.md`.

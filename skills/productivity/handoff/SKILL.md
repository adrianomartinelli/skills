---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS (`$TMPDIR`, else `/tmp`; `%TEMP%` on Windows) - not the current workspace.

Start the document with session metadata so the work can be traced back: Claude session ID (`${CLAUDE_SESSION_ID}`), timestamp, host, cwd, git branch, commit, and number of uncommitted files. Write `unknown` for a value you cannot get; never invent a session ID.

Check facts that can change (`git status`, test results, running Slurm jobs) before reporting them. If you did not check something, say "not checked".

Include a "suggested skills" section in the document, naming which skills the next agent should call the Skill tool for.

Do not duplicate content already captured in other artifacts (specs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.

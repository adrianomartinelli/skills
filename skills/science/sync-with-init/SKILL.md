---
name: sync-with-init
description: Pull the latest project-init template changes into a project built from it, by
  cherry-picking each commit, merging by hand the files the project owns, and asking the user
  where content goes when the template deletes or moves a file. Also sends project-side
  improvements (for example glossary terms) back to project-init. Use for "sync with init", "pull
  init", "pull in project-init changes", "update from the template", "port this back to init".
---

# Sync with init

Template changes arrive as cherry-picks from the `init` remote
(`docs/reference/template-updates.md`), never as `git pull init main`. This skill covers the
parts that procedure leaves out: finding what is new, deciding who owns each file, migrating
content that the template removed, and repairing what the sync breaks. It touches only the `init`
remote. It does not update the skills plugin.

## 1. Find what is new

1. `git fetch init`. If the `init` remote is missing, run `bash scripts/setup-init.sh`.
2. Find the last synced template commit. Each sync records it as a trailer on its last commit
   (step 9):
   `git log main --format='%(trailers:key=Synced-init,valueonly)' | grep -m1 .`
   If no trailer exists, take the newest template hash in a `(cherry picked from commit <sha>)`
   line or in a subject such as "Sync project-init <sha>", and confirm it with the user. Never
   guess the base.
3. List the new commits with `git log --oneline <last>..init/main`. Run `git show --stat` on each.
4. For each template-owned file, compare the project's copy with the template's copy at `<last>`
   (`git show <last>:<file> | diff - <file>`). If they are identical, the cherry-pick applies
   cleanly. Any difference needs a hand merge.

## 2. Propose, then wait for approval

Write a numbered list with these groups:
- **A. Cherry-pick as-is:** template-owned files that step 1.4 found identical.
- **B. Cherry-pick:** other template files (scripts, `docs/agents/`, `docs/reference/`).
- **C. Hand merge:** files that the project owns or has changed.
- **D. Deleted or moved by the template:** for each file that holds project content, propose a
  destination for each section (step 6), or propose to delete the section with the reason.
- **E. Skip:** with the reason for each, for example commits that touch only the template's
  `WORKTREE.md`.

Name each decision that only the user can make, with a recommendation. Group D always needs the
user. Do not edit anything before the user approves.

## 3. Claim the work (PRC-5 to PRC-7)

1. Read the `WORKTREE.md` scope line of each remote branch, and look for overlap with this sync.
2. Run `git worktree add -b template-sync ../<repo>-template-sync main`.
3. Push the status line and the scope line before the first substantive edit.

## 4. Send project improvements to init first

If the project adds something the template should have (for example `GLOSSARY.md` terms, a
policy fix, a generic helper):
1. Make the change in a checkout of project-init. Remove the project-specific assumptions.
2. Commit it as a focused change that names its source (`Ported from <owner>/<repo>.`), and push
   it to project-init `main` (PRC-8).
3. `git fetch init`, and cherry-pick it into the project together with the other template commits.

The project then holds the same commit as the template, not a fork of it.

`GLOSSARY.md` is cumulative across projects. Never drop another project's terms. When a project
term clashes with a shared term (for example a local "run root" that means `OUTPUTS_DIR`), rename
the project term and add an `_Avoid_` line for the old name. Do not change the shared term.

## 5. Cherry-pick in order: `git cherry-pick -x <c>`

| Situation | Resolution |
|---|---|
| Empty pick (the change is already there) | `git cherry-pick --skip`. Check whether a later commit puts the change back. |
| Conflict in a template-owned file (`AGENTS.md`, `CODING_STANDARDS.md`, `GLOSSARY.md`, `docs/agents/`, `scripts/setup-init.sh`) | `git checkout --theirs`. Step 4 has already sent the project's additions upstream. |
| Conflict in a project-owned file (`README.md`, `WORKTREE.md`, `.env.example`, `.gitignore`, `docs/retrospective.md`) | `git checkout --ours`, then apply the template's intent by hand. |
| Change in `src/project_name/*` (shown as `DU`) | `git rm` the placeholder path. Apply the same change to `src/<package>/` by hand. |
| Template deletes a file that holds project content (`UD`, for example `docs/status.md`) | Keep the file in this pick (`git checkout --ours`). Migrate it as the user approved in step 2 (step 6), then `git rm` it in its own commit. |

Look at the net effect of the commit sequence, not only each commit. Example: one commit removes
`.envs/` from `.gitignore` and a later commit adds it back, so the result must have it.

## 6. Migrate content the template removed or moved

Only as the user approved in step 2, group D:
- Open work, open questions, and plans belong on GitHub issues: comment on the existing issue,
  or open a new one (with its blockers). Before you comment, check that the issue does not
  already say it.
- A summary of finished experiments belongs in a closing comment on their parent issue. A claim
  that later work relies on belongs in `docs/findings.md`.
- Facts about one directory belong in a `README.md` in that directory. Locations belong in the
  layout block of the root `README.md`.
- When the migration makes an issue moot, close it with a comment that names the commit.
- Delete the file only when no pointer to it remains (step 7).

## 7. Find stale references

1. `git grep -nE '<every moved or deleted file>|<every renamed term>'`, excluding `docs/prs/`,
   `third_party/`, `vendor/`, ADRs, and closed logs.
2. Also grep for section names that the old `AGENTS.md` had and the new one lacks
   (`git grep -n 'AGENTS\.md, "'`). Code comments cite those.
3. Fix each pointer. A rule citation becomes a bare rule ID ("CFG-1", not "AGENTS.md, CFG-1" or
   "AGENTS.md, Environment and config"), because rules move between files. If the rule was
   removed, name the former rule and the issue that removes the code.

## 8. Check the tooling

- Compare each `rev:` in `.pre-commit-config.yaml` with `pixi run <tool> --version`. If they
  differ, the hook and pixi fight on every commit. Ask the user, then raise the pin and reformat
  in one commit.
- If a hook rewrites files during a commit, inspect the change, stage it, and commit again.
- Do not run `pre-commit run --all-files` over preserved records (`docs/run-artifacts/`). If it
  ran, `git checkout -- <those paths>`.

## 9. Finish

1. `git fetch init` again. Other sessions push to project-init too. Pick up any commits that
   arrived during the sync, or report them.
2. Run `ruff check`. Run tests that train models only through the scheduler (RUN-9). A sync that
   changes only docs and comments needs no training test.
3. Check `git diff init/main -- AGENTS.md CODING_STANDARDS.md GLOSSARY.md`. It must be empty, or
   every line of it must be an intended local divergence.
4. Record the base for the next sync. Give the sync's last commit the trailer
   `Synced-init: <full sha of init/main>`, with `git commit --trailer`.
5. Rebase onto `main` and set the `WORKTREE.md` status. Merge only when the user approves.
6. Update every agent memory that names a file the sync moved or deleted.
7. Report to the user: the template range synced, the files in each group, and what is left for
   the user.

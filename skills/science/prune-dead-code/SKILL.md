---
name: prune-dead-code
description: "Find dead code and outdated documentation in a Python repo, then open two PRs: one that only deletes dead code (zero added lines), and one that fixes stale docstrings, comments and README sections. Use when the user asks to find or remove dead code, unused functions/imports/files, clean up a repo, check whether docs or the README are outdated, audit docstrings against the code, or prepare a cleanup PR, even if they only say 'tidy up this repo' or 'what can I delete'."
---

# Prune dead code and stale docs

Goal: two reviewable PRs.

1. **Deletion PR** — removes dead code and nothing else, as a series of focused commits (one per obsolete module, feature or group of helpers). Every hunk is a removal; the only lines it may add are shortened import lines. A reviewer can approve it by asking one question per commit: "is this really unused?"
2. **Docs PR** — fixes docstrings, comments and README text that no longer match the code. Separate, because rewriting text needs a different kind of review than deleting code.

Keep them apart. Mixing a doc rewrite into the deletion PR breaks the "only deletions" promise that makes it fast to review.

## 1. Before you start

- Work from an up-to-date default branch with a clean tree. If the tree is dirty, stop and tell the user.
- Read the repo's own rules: `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `docs/todo.md` or similar, to learn which code is vendored and which code people mean to keep.
- Dead code does not stay in the code base "for later". Code that a todo or note reserves for future work, or that a rule says to archive, is still deleted when nothing reaches it: git history keeps it, and the focused commit message (step 4) makes it easy to find again. Mention such code in the PR body so its owner sees it go.
- Out of scope: vendored code and git-ignored files (see step 2). Neither is analysed, deleted or reported.
- Do not run the test suite; another skill handles testing.

## 2. Find dead-code candidates

All commands need only `uv`, no project config. Tools find candidates; the verification in step 3 decides.

First build the file list once and pass it to every tool. `git ls-files` drops git-ignored files; the `grep` drops vendored code, guessed from folder names. Test folders are dropped too, so code used only by its own tests still shows up. Add any vendored folder the repo rules name that the pattern misses (e.g. `cq1/`):
```bash
git ls-files '*.py' | grep -viE '(^|/)(vendor(ed)?|third_?party|external|extern|_vendor|site-packages|tests?)/' > /tmp/prune-files.txt
```
Pass the list with `xargs`, which works in bash and zsh alike (zsh does not split an unquoted `$FILES`, and the tools then fail or silently check nothing):

Primary — the candidate list comes from this:
- `xargs uvx deadcode < /tmp/prune-files.txt` — unused functions, classes, methods, variables, imports. The list covers every caller directory (`src/`, `scripts/`, `workflow/`…); running on `src/` alone floods the result with false positives when scripts or a Snakefile are the real callers.

Supplements — catch what deadcode does not:
- `xargs uvx vulture --min-confidence 60 < /tmp/prune-files.txt` — second opinion and unreachable code. A symbol both tools flag is a stronger candidate; expect false positives for entry points and things loaded by name.
- `xargs uvx ruff check --select F401,F841,F811,ERA001 < /tmp/prune-files.txt` — unused locals, redefinitions, commented-out code (`ERA001`).

Also look for files nothing imports (grep each module's dotted path and stem) and `if False:` branches. If no tool can run (no network, no `uv`), fall back to grep for each top-level `def`/`class` name across the repo.

## 3. Verify every candidate

A candidate is dead only when nothing working reaches it. A caller that is itself already broken (it imports names that no longer exist, so it fails at import) does not keep code alive — that caller is dead too: delete it in its own commit ("Remove broken <file> (imports removed <name>)").

Before you delete, grep the **whole repo** (not only `src/`, and including tests and vendored folders, since they can still call into your code) for the name and check these indirect uses, which static tools miss:

- Public API: listed in `__all__`, re-exported in a package `__init__.py`, or the repo is a library others import. Library public symbols are not dead just because this repo does not call them — report them, do not delete them.
- Non-Python callers: `Snakefile`/`*.smk` (`script:`, `shell:` lines), shell and Slurm scripts, Makefiles, CI configs.
- Entry points: `[project.scripts]`, `[project.entry-points]`, `setup.py`, `console_scripts`, CLI registries.
- Strings: config files (YAML/JSON/TOML), `class_path:` entries (jsonargparse/Lightning), `getattr`, `importlib`, Hydra `_target_`, registries filled by decorators, pytest fixtures and plugins, Snakemake/Slurm scripts, notebooks.
- Dunder methods, `@property`, `@abstractmethod` overrides, signal/callback handlers.

Classify each candidate as **dead** (delete), **unsure** (list in PR body, do not delete) or **alive** (drop). "Unsure" means you could not establish whether something reaches the code — not that someone might want it later. When reachability is in doubt, unsure.

If deleting a symbol leaves its tests orphaned, delete those tests in the same commit — they are dead too. If it leaves an import unused, delete that import as well.

## 4. Build the deletion PR

If nothing is verifiably dead, open no deletion PR. Say so, and give the "unsure" list instead — an empty result after careful checking is a valid outcome.

- Branch: `prune/dead-code-<YYYY-MM-DD>`.
- One commit per coherent unit: a whole obsolete module, one retired feature across files, or a batch of unused helpers in one module. Unused imports left behind by a deletion go in that same commit; stray unused imports elsewhere go in one final "Remove unused imports" commit. Message format, so `git log --grep` finds it later:
  ```
  Remove obsolete <module/feature> (<short reason>)

  Deleted: src/pkg/legacy_io.py (read_csv), tests/test_legacy_io.py
  Why dead: no imports anywhere; replaced by pandas reader in v0.2.
  Restore: git log --grep 'Remove obsolete <module/feature>' to find this commit, then git revert it
  ```
- Remove whole lines only. Do not reformat, re-indent or rewrite surrounding code. One exception: an import line that names several things may be shortened to drop the names a deletion left unused (`from x import a, b` → `from x import a`). Any other changed line (a call site, an `else:` that becomes empty) means the target is not cleanly dead: move it to "unsure".
- Check the promise holds:
  ```bash
  git diff -U0 <base> | grep '^+[^+]' | grep -vE '^\+\s*(from|import) '   # must print nothing
  ```
- Grep once more for every deleted name and file path. Any remaining reference from working code means the deletion was wrong: restore it and mark it alive.
- Commit, push, and open the PR with `gh pr create`. Body:

  ```markdown
  ## Deleted (verified unused)
  | Symbol / file | Why it is dead |
  |---|---|
  | `pkg/mod.py::old_helper` | no references outside its own definition; not in `__all__` |

  ## Commits
  One line per commit: `<sha> Remove obsolete …`

  ## Reserved code that was deleted
  - `pkg/segment.py::cytoplasm_mask` — `docs/todo.md` kept it for M15; restore from <sha> if needed

  ## Not deleted — please check
  - `pkg/api.py::legacy_load` — only referenced in `configs/old.yaml` (is that config still used?)

  ## Checks
  - Only deletions (plus shortened import lines)
  - No remaining references to deleted names (grep)
  - Tests not run here (handled separately)
  ```

## 5. Find stale documentation

Do this against the code **after** the deletions, so docs that describe deleted code show up too.

- **Docstrings**: compare each documented parameter, return value and raised exception with the actual signature and body. Flag params that no longer exist, missing params, wrong defaults, wrong types, descriptions of behaviour the body no longer has.
- **README / docs/**: try every install command, CLI invocation and code snippet against the code (do flags exist? do imported names exist? do referenced files and paths exist?). Flag mentions of removed modules, functions, config keys, scripts.
- **Comments**: TODOs that are done, comments describing code that changed.

Fix only what is verifiably wrong. Do not restyle prose or add new documentation the user did not ask for.

## 6. Build the docs PR

- Branch `prune/stale-docs-<YYYY-MM-DD>`, based on the default branch (not on the deletion branch) unless a doc fix only makes sense after a deletion — then base it on the deletion branch and say so in the body.
- Body: a table of `file:line — what was wrong — what it says now`, plus a list of doc problems you saw but could not fix with confidence.

## 7. Report back

Tell the user, briefly: both PR links, counts (symbols/files deleted, lines removed, docs fixed), and the "unsure" list. If `gh` is not authenticated or there is no remote, leave the branches local and say so.

If the user asked only to *check* ("are there dead functions?", "is the README outdated?"), stop after steps 3 and 5 and report findings — do not branch, commit or push without being asked.

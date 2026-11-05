# Policy review: example signs of violations

The rules are in the "Policy" sections of the project's `AGENTS.md` and `CODING_STANDARDS.md`.
This file does not repeat them. Each line below starts with
a rule ID and gives one example sign in a diff that points to a violation of that rule. Earlier
reviews and the rules themselves are the source of these examples.

The list is not complete, and many rules have no line. A reviewer checks the diff against the text
and the Reason of every rule in its group, and uses these signs only as examples of what a
violation can look like. A sign is not a finding: report a violation only when the code breaks the
rule itself.

Rule IDs are never renumbered (see "How to read the Policy section" in `AGENTS.md`). When a rule is
deleted, delete its lines here too.

- CFG-1: Code, or a YAML file under `configs/`, contains a machine path, hostname, account name, or
  credential as a literal.
- CFG-2: Python code outside `src/<project_name>/settings.py` reads `os.environ`, `os.getenv`,
  `os.path.expandvars`, or `environ.get`.
- CFG-3: The diff adds a `.env` key and does not add a matching line to `.env.example`.
- CFG-4: A run config model sits in a module of its own (for example `config.py` or `configs.py`),
  not in the module that uses it.
- CFG-5: A YAML config for `scripts/<script>.py` sits outside `configs/<script>/`.
- CFG-6: A value from `Settings` or from the environment selects what a run computes, for example a
  dataset, a model variant, or a hyperparameter.
- CFG-7: A script calls `cfg.as_dict()` or `instantiate_classes`, builds `Config(**cfg[...])`, uses
  `argparse`, or builds a parser without `add_class_arguments`.
- CFG-7: For the full check, read the "Writing an endpoint" section of
  the `jsonargparse` skill and compare each changed script with it.
- PTH-1: Code outside `src/<project_name>/paths.py` builds a location under a root with a `Path(...) / ...` chain, an f-string that contains `/`, or
  `os.path.join`.
- PTH-2: The diff adds a kind of output (for example a report, a dataset, or a figure set) and no
  paths class for it.
- PTH-3: A paths class sits outside `paths.py`.
- ART-1: Code calls `unlink`, `os.remove`, `shutil.rmtree`, `rmdir`, or `rm` on a path that can be
  outside `OUTPUTS_DIR` (for example `data/processed/`) or that can be `OUTPUTS_DIR` itself.
- ART-1: Code configures a third-party writer that deletes in a directory outside `OUTPUTS_DIR`, for
  example Lightning `ModelCheckpoint` with `save_top_k` other than `-1`.
- ART-2: Code writes, moves, or deletes a path under `DATA_DIR` that the project did not create, for
  example under `data/raw/`, or writes to a path outside every `Settings` root.
- ART-6: A script or a command deletes paths that it selects with a loop, a glob, or a predicate,
  for example every run directory without `summary.json`. Delete through the `delete` skill.
- SRC-1: A script defines a function that does file or network I/O.
- SRC-2: A script defines a function that a second script also needs, or a function complex enough
  to need its own test.
- SRC-3: A module under `scripts/` imports from another module under `scripts/`.
- SRC-3: Two scripts contain the same CLI parsing or the same logic.
- SRC-4: The diff adds behaviour to `src/` and adds or changes no test in `tests/`.
- STY-1: The diff adds a helper, base class, or option that has exactly one caller.
- STY-4: Code calls `.get(key, default)` or `getattr(..., default)` on a field that the contract
  requires.
- STY-5: Code skips an item (`continue` in an `except`, `if x is None: continue`) and raises no
  error and reports nothing.
- STY-6: Code uses `except Exception` or a bare `except:`, or puts `try` around a loop over data
  items.
- STY-7: Code starts a recursive search for data or dependencies at `Path.home()`, `~`, `/`, or
  `/usr`.
- STY-8: A comment repeats what the next line does.
- STY-9: The diff weakens the `ruff` configuration or `.pre-commit-config.yaml`.
- STY-9: The pre-commit hook enforces the rest of this rule. Do not report formatting or lint
  issues.
- STY-10: Code writes tables as CSV or pickle, item manifests as pickle, or configs as JSON.
- STY-11: Code reads a full large raw table (`pd.read_parquet(path)` with no `columns=`, `read_csv`
  with no chunks) where item-level or column-level access exists.
- STY-12: New code uses `Union[`, `Optional[`, or `List[`.
- STY-13: A new module, class, function, or method has no docstring, or the first line of its
  docstring is longer than 80 characters. `tests/test_docstrings.py` finds both.
- RUN-2: The diff adds a config field that looks execution-only (for example workers, device, log
  interval, or a progress bar) and does not add it to `_identity_exclude`.
- RUN-2: The diff adds a field to `_identity_exclude` with no reason.
- RUN-3: Code computes the identity in more than one place, or computes it again from a config
  downstream.
- RUN-4: A YAML file under `configs/` contains an identity hash.
- RUN-5: A run does not write its resolved config into its run root.
- RUN-6: Code skips or submits work because a hash path exists.
- RUN-7: A field is in a planned config but not in historical configs, and code resolves it
  silently. Examples: a default fills it, or the comparison ignores it.
- RUN-8: The diff edits a committed collector table by hand.
- RUN-10: The diff sets `--mem`, `--time`, or `--cpus-per-task`, and no measurement in `docs/` or in
  the commit message supports the values.
- RUN-11: An `sbatch` or `srun` call sets `--chdir` to the live checkout, or a job body runs from
  the repository root instead of a snapshot.
- PRC-1: On a branch other than `main`, the first line of `WORKTREE.md` does not have the required
  shape. Read the line with `git show <branch>:WORKTREE.md`.
- PRC-2: The first line of `WORKTREE.md` uses a token that its comment block does not declare.
- PRC-3: The first line of `WORKTREE.md` does not describe the current state of the branch.
- PRC-7: The diff changes many files on a branch whose `WORKTREE.md` has no Scope line.
- PRC-9: A commit message or a code comment states a lesson that applies beyond this change, and
  `docs/retrospective.md` has no entry for it.
- PRC-10: The diff changes or deletes existing lines of `.agent-sessions`.
- LEG-1: A reader branches on which version of the project's own code wrote the data. Examples: a
  schema-version key, `if "new_field" in d`, an old-versus-new dict layout, a `LEGACY_*` mapping, or
  a comment such as "written before X".
- LEG-1: Code changes its behaviour by the version of the project's own artifacts, configs,
  checkpoints, or tables. A check of a third-party API version is not a violation.
- LEG-1: The author of legacy code does not think "I am adding a compatibility shim". The author
  thinks "I am reading the existing data correctly". Look for the shape, not the intent.
- LEG-2: A reader returns a value that the artifact does not contain. It substitutes, defaults,
  normalizes, or repairs a field because a known writer wrote that field wrong.
- LEG-3: A function, flag, field, config key, or default exists only to make older input parse.
- LEG-4: A guard detects an old shape, and no artifact of that shape remains.

---
name: audit-tests
description: "Audit a repo's test suite (tests/ folder) and report tests that are obsolete, misconfigured, superficial, hacky or unclearly defined, plus tests that should be merged, parametrized or moved into fixtures. Report only, changes nothing. Use when the user asks to review, audit, clean up or assess the quality of their tests, asks which tests are useless, outdated, flaky-looking, redundant or patchy, wants to know if tests still test what they claim, or says things like 'our tests are a mess', 'are these tests any good', 'what tests can I delete', even if they don't say 'audit'."
---

# Audit tests

Goal: one ranked report that tells the user, per finding, **which test**, **what is wrong**, **why it matters**, and **what to do** (delete, rewrite, merge, parametrize, move to fixture, fix config). Change no files; the user decides.

A test earns its place only if it would fail when the behaviour it names breaks. Every category below is a way a test stops doing that, or costs more than it gives.

## 1. Orient

- Find the test runner and config: `pyproject.toml` (`[tool.pytest.ini_options]`), `pytest.ini`, `setup.cfg`, `tox.ini`, `conftest.py` files, CI workflow files. For non-Python repos, the equivalent (`jest.config`, `vitest`, `Cargo.toml`, ...). The categories are language-agnostic; the examples are pytest.
- Map tests to source: which module each test file targets. Note source modules with no tests at all (one line in the report, not the focus).
- Run the suite once if it is cheap and safe (no network/cluster/GPU side effects): `pytest -q -rA --durations=15` gives skips, xfails, warnings and slow tests. If the full run crashes or errors at collection, run each test file on its own to separate broken files from healthy ones. If nothing runs, say so and continue statically. Optional and very useful: `coverage run -m pytest && coverage report -m` to see which tests touch nothing of `src/`.
- Read `git log --format='%h %ad %s' --date=short -- tests/ src/` briefly: tests untouched for years while their target was rewritten are prime obsolete suspects.

## 2. Look for these problems

Read every test file. For each test, ask: *what behaviour does the name claim, and would this test fail if that behaviour broke?*

**Obsolete**
- Tests a function/class/flag/config key that no longer exists, was renamed, or is only kept alive for the test (grep the target in `src/`).
- Skipped/xfailed with a stale reason ("until #123 is fixed" where #123 is closed, "TODO re-enable", version checks for Python/libs the project no longer supports).
- Asserts old behaviour that the code no longer has but still passes by accident (e.g. tests a deprecated code path or a shim).
- Duplicates another test after a refactor (same inputs, same assertion, different name).

**Superficial (would not catch a real bug)**
- No assertion, or only `assert result is not None`, `assert isinstance(...)`, `assert len(x) > 0`, `assert True`.
- Only checks that no exception is raised, when the function returns something checkable.
- Mocks the unit under test, or mocks so much that the test only checks the mocks talk to each other.
- Asserts on a value the test itself just set up (tautology), or recomputes the expected value with the same code as the implementation.
- Snapshot/golden-file tests whose golden file is regenerated blindly or is huge and unreviewed.

**Hacky**
- `time.sleep`, retries, or loose tolerances to hide flakiness; order-dependent tests sharing module-level state.
- Broad `try/except: pass`, `pytest.raises(Exception)`, `# noqa`/`type: ignore` sprinkled to make it pass.
- Monkeypatching private internals, editing `sys.path`, `os.chdir` without restore, writing to the repo instead of `tmp_path`.
- Hard-coded absolute paths, usernames, hostnames, dates, random seeds without explanation; dependence on network or a local dataset without a skip marker.
- Commented-out assertions or commented-out test bodies.

**Misconfigured**
- Not collected: file or function not matching `python_files`/`python_functions`, class with `__init__`, test inside a helper module, duplicate test names shadowing each other (later `def test_x` overwrites earlier one in the same file).
- Markers used but not registered, or registered but never used; `--strict-markers` missing.
- `filterwarnings = ignore` blanket rules that hide real deprecations.
- Fixtures with wrong scope (session-scoped mutable state), unused fixtures, fixtures shadowed across `conftest.py` files, `autouse` fixtures with surprising side effects.
- `parametrize` ids missing so failures read as `test_x[3]`; parametrize cases that are identical.
- `testpaths`/`addopts` that silently exclude directories.

**Not clearly defined**
- Name does not say what is checked (`test_1`, `test_basic`, `test_it_works`, `test_model`).
- One test asserts many unrelated things; a failure would not tell you what broke.
- Magic numbers in expected values with no hint where they come from.
- Long setup inline that hides the one line that matters.

**Structure: merge / parametrize / fixture**
- Several tests identical except for inputs → one `@pytest.mark.parametrize`.
- Same setup copy-pasted across tests or files → fixture (in the nearest `conftest.py` that covers all users).
- Helper functions in test files duplicating `src/` logic → use the real function or a fixture.
- Test files that mirror no source module any more, or one huge file covering many modules → split or relocate.

Use these as a checklist, not a cage: report anything else that makes a test cost more than it protects.

## 3. Verify before reporting

Each finding must hold up to a skeptical reviewer. Before listing a test as obsolete, grep the whole repo (src, configs, scripts, notebooks) for its target. Before calling an assertion superficial, check that a stronger one is actually possible. If you only *suspect* something (e.g. flakiness you cannot reproduce), put it under "Worth a look", not under findings.

A cheap, strong check for "superficial": mentally (or actually, on a scratch copy) break the target — return a constant, flip a sign, drop a branch. If the test would still pass, it is superficial. Say what mutation survives.

## 4. Report

Write the report to the chat (and to `tests_audit.md` in the repo root only if the user asks for a file). Rank by value: findings that hide real bugs first (superficial, not collected, swallowed failures), then obsolete, then hacky, then structure and naming.

```markdown
# Test audit: <repo>

<2–3 sentences: suite size, how it ran (pass/skip/xfail counts, runtime), overall health, the biggest problem.>

## Findings

| # | Test | Category | Problem | Fix |
|---|------|----------|---------|-----|
| 1 | `tests/test_io.py::test_load` | Superficial | Only asserts `df is not None`; a loader returning an empty frame passes. | Assert shape and a known value from the fixture file. |
| 2 | ... | | | |

## Merge / parametrize / fixture opportunities
- `test_parse_int`, `test_parse_float`, `test_parse_str` in `tests/test_parse.py` → one parametrized test.
- `tmp config dict` built identically in 6 tests across 3 files → `config` fixture in `tests/conftest.py`.

## Worth a look (unverified)
- ...

## Untested source modules
- `src/pkg/foo.py`, ...
```

List only tests with a problem. Do not list healthy tests or files, and do not praise the suite: the reader wants to see what needs work, fast. Drop any section that would be empty. Keep each row to one line of problem and one line of fix, specific enough that someone can act on it without re-reading the test. Group many identical issues ("14 tests named `test_N`") into one row rather than repeating them.

End by offering the next step (e.g. "want me to apply the parametrize/fixture merges?" or "open a PR deleting the obsolete ones?"), but do not do it unasked.

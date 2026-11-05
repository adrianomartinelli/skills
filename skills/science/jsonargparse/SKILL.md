---
name: jsonargparse
description: How this project's jsonargparse CLI entrypoints behave and how to write them. Use when invoking a script that takes `--config` (composing config files, CLI overrides, building the command line for a shell, sbatch, or Snakemake call, or debugging why an override had no effect or a config key "is not accepted"), and when writing or editing an entrypoint or the pydantic config models it parses into (`ArgumentParser`, `add_class_arguments`, `instantiate`, `Union` / discriminated-union fields).
---

# jsonargparse

Read only the section for your task:

- [Invoking an endpoint](#invoking-an-endpoint): building a command line or config files for an
  existing script.
- [Writing an endpoint](#writing-an-endpoint): creating or changing a script's parser or the config
  models it parses into.

Every behaviour below was tested on **jsonargparse 4.52.0 with pydantic 2.12.5**, using
`parser_mode="omegaconf"`. The version is unpinned, so re-check a behaviour you depend on after an
upgrade (`pixi run python -c "import jsonargparse; print(jsonargparse.__version__)"`).

## Invoking an endpoint

> [!CAUTION]
> **Never override a single subfield of a union field.** `--train.strategy.shared 9` resolves to the
> first union member that has that key, silently discarding the member the config file selected,
> even after `--train.strategy B`. Set the whole field in one value instead
> (`--train.strategy '{class_path: pkg.B, init_args: {b_param: 5, shared: 9}}'`), or write an
> edited copy of the config file for each job.

Every invocation follows these steps:

1. **Build the command line** using the rules below.
2. **Confirm the resolved config once:** append `--print_config` to that exact command and run it.
   It prints the fully merged config and exits without doing any work. Check the values you set
   and, for a union field, the member that was selected.
3. **Run the command without `--print_config`** only if the config resolved as expected.
   Otherwise fix the command and repeat step 2.

How the command line resolves:

- **Arguments apply left to right; the last one wins.** An override placed *before* `--config` is
  silently overwritten by the file.
- **Nested model sections merge; they don't replace.** `--config base.yaml --train train.yaml`,
  `--train.optim.lr 0.1` and `--train.optim '{lr: 0.1}'` each change only the keys they give. Every
  other key keeps its value from `base.yaml`.
- **`--config` can repeat.** `--config defaults.yaml --config run.yaml` merges the files in order.
  Use this to layer one run's differences on shared defaults instead of copying the defaults.
- **`dict` and `list[...]` fields are replaced whole.** A new value for one of these fields
  replaces it entirely, with no merge.
- **Unknown keys are an error** (`Option 'x.y' is not accepted`). A config file may contain only
  the sections that this script's parser declares.

## Writing an endpoint

Write one `pydantic.BaseModel` per config section. Add each one under its own key with
`add_class_arguments`, build the namespace with `instantiate`, and read values as
`init.<key>.<field>`:

```python
from jsonargparse import ArgumentParser
from project_name.pipeline import TrainConfig, run_train
from project_name.settings import Settings

parser = ArgumentParser(parser_mode="omegaconf")
parser.add_argument("--config", action="config")
parser.add_class_arguments(TrainConfig, "train")

def main() -> None:
    init = parser.instantiate(parser.parse_args())
    paths = run_train(settings=Settings(), config=init.train)

if __name__ == "__main__":
    main()
```

- **Use `instantiate`, not `instantiate_classes`.** `instantiate_classes` has been deprecated since
  4.49 and will be removed in v5. Don't build `cfg.as_dict()` and then construct
  `Config(**cfg["key"])` by hand.
- **Use a nested `BaseModel` when partial overrides are expected.** Fields typed `dict` or `list`
  can only be replaced whole.
- **Union fields:**
  - When the field's default is one member, YAML that selects a *different* member as a plain dict
    (`{name: b, ...}`) is rejected. Write it in `class_path` / `init_args` form. The rejection is
    loud, not silent.
  - Keep values that vary per job (sweep axes) in plain fields, outside any union. Per-job
    overrides of a union subfield go wrong silently (see the caution under "Invoking an endpoint").
  - After `instantiate`, assert the resolved member
    (`assert isinstance(init.train.strategy, B)`) before expensive work starts.

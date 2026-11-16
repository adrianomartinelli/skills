# Patterns: code for agentic-system-design

One runnable example per section of `SKILL.md` marked *(P1)* to *(P7)*. Run with pydantic 2.14,
pandera 0.36, OmegaConf 2.4. The rules behind them are `DES-1` to `DES-7` in the project's
`AGENTS.md`.

## Dummies (work order, step 3)

```python
def measure(config: Metrics, read: dict[str, Artifacts], out: Path) -> dict[str, pd.DataFrame]:
    """Dummy: the real signature, a schema-valid table, no logic."""
    acqs = read["input"].read("acquisitions", ["acq_id"])
    return {"acq_metrics": acqs.assign(tissue_fraction=0.5)}
```

## P1 Config: a fixed model and a tunable model, flat

A fixed model (the code's defaults; changing one is a commit) and a tunable model (what
the agent sets), both with `extra="forbid"`. The tool's config inherits both. What the
user wants the agent to choose goes in the brief. The agent's patches merge key by key
with `OmegaConf.merge`, in log order. A `missing` error means the config is incomplete. Every other
error refuses the patch, and nothing is appended to the log.

```python
class MetricsFixed(BaseModel):
    model_config = ConfigDict(extra="forbid")
    quantiles: list[float] = [0.1, 0.5, 0.9]       # fixed: a commit changes it

class MetricsTunable(BaseModel):
    model_config = ConfigDict(extra="forbid")
    nuclear: list[str]                              # no default: the agent chooses
    batch: Batch

class Metrics(MetricsFixed, MetricsTunable): ...    # the tool's config, flat

merged = OmegaConf.to_container(OmegaConf.merge({}, *patches, patch))
try:
    MetricsTunable.model_validate(merged, context={"panel": panel})
except ValidationError as e:
    missing = [x for x in e.errors() if x["type"] == "missing"]   # -> "ok; incomplete: [...]"
    other = [x for x in e.errors() if x["type"] != "missing"]     # -> refused, nothing appended
```

Run output: `{quantiles: [0.5]}` is refused (`Extra inputs are not permitted`).
`{batch: {covariates: [slide]}}` followed by `{batch: {group_by: patient}}` keeps both keys.

## P2 Cross-references: a validator that reads the validation context

The field's own validator reads `info.context`. The caller passes the context once.

```python
@field_validator("nuclear")
@classmethod
def in_panel(cls, v: list[str], info: ValidationInfo) -> list[str]:
    if missing := [c for c in v if c not in info.context["panel"]]:
        raise ValueError(f"not in the panel: {missing}")
    return v
```

Gotcha: every validation of that model needs the context, including the frozen config built from
it. A model constructed without the context fails with `'NoneType' object is not subscriptable`.

Variants (two models, two methods) are a discriminated-union field: see the `contract-design`
skill.

## P3 An append-only decision log; state is a replay

One `decisions.yaml` per workspace, append-only. The command writes each entry, with
`at` and `by` and the `input` and `output` manifests it read and wrote. A
refused call appends nothing. A later entry is the revision. State is computed by replaying the
log.

```yaml
- {command: set_config, name: m1, patch: {nuclear: [DNA1]}, reason: "brief: DNA1 is the intercalator",
   input: [input/datapackage.json], at: 2026-11-12T10:07:12Z, by: 5e0c...}
- {command: measure, name: m1, input: [input/datapackage.json], output: [3f9a.../datapackage.json], ...}
```

```python
def current_output(entries, name):
    """The output of the name's latest tool entry; finished when its manifest exists."""
    (*_, last) = [e for e in entries if e.get("name") == name and "output" in e]
    return last["output"][0]
```

The rule `by = CLAUDE_CODE_SESSION_ID, else "human"` covers sessions and humans alike.

## P4 Run identity: an output folder per frozen config

The folder is the hash of the frozen config. The instance's name and its provenance are in
the config but excluded from the hash, so two names with the same config share one output. The
manifest is written last and is the only "finished" marker. A finished folder is reused and an
unfinished one is rewritten.

```python
class Frozen(Metrics):
    name: str
    provenance: dict
    _identity_exclude: ClassVar[frozenset[str]] = frozenset({"name", "provenance"})

def run_tool(root: Path, config: BaseModel, compute) -> Path:
    out = root / identity_hash(config)
    if (out / "datapackage.json").exists():
        return out                                   # finished: reuse
    out.mkdir(parents=True, exist_ok=True)           # unfinished: rewrite
    tables = compute(config)
    for name, table in tables.items():
        table.to_parquet(out / f"{name}.parquet")
    (out / "datapackage.json").write_text(json.dumps({"resources": sorted(tables)}))  # last
    return out
```

## P5 An item call is validated by the artifact's own schema

The artifact's state is its items (every value null) with every logged patch applied, key
by key, in log order. A call validates only the rows it names, with the artifact's pandera schema:
`not_nullable` means incomplete, and any other failure refuses the call. Export validates the
whole table with the same schema. There is no separate patch model and no special check.

```python
t = table(items, entries + [entry])                 # replay, then this call
try:
    ChannelStatus.validate(t[t.target.isin(ids)], lazy=True)
except pa.errors.SchemaErrors as e:
    fc = e.failure_cases
    if len(fc[fc.check != "not_nullable"]):
        raise Refused(...)                          # nothing appended
    # else: append, report "incomplete"
```

Run output: `{role: nucleus}` is refused (`isin`), `{role: nuclear}` gives `ok; incomplete:
[status]`, and the export validates once every channel has a role and a status.

An empty value is null. Why a call was made is its reason, written in words.

## P6 A status annotates; each tool filters

Status artifacts are required inputs and only annotate. The input keeps every item. Each
tool applies its own filter, stated in its docstring. Statuses from several stages are joined on
their key when they are read, never copied into one wide artifact.

```python
kept = cells.merge(acq_status, on="acq_id").query("status != 'exclude'")[cells.columns]
```

## P7 Relations between artifacts: declared once

A schema sees one table. A relation sees two. Declare each relation once and check it wherever both
artifacts meet: when an input is set up, and at export.

```python
RELATIONS = [("cells", "acq_id", "acquisitions", "acq_id"), ...]

def check_relations(tables):
    return [f"{c}.{k} not in {p}.{q}: {bad}"
            for c, k, p, q in RELATIONS if c in tables and p in tables
            if (bad := sorted(set(tables[c][k]) - set(tables[p][q])))]
```

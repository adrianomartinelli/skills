---
name: contract-design
description: Design principles for the boundaries between programs and the contracts that cross them, so that what a writer, reader, CLI, config or API promises can be checked. Use when you write or change code that writes a file another program reads, reads a file another program wrote, defines the arguments or output of a CLI, defines a config or request model, or exposes an API that other code calls. Also use when a reader patches what its writer produced, or when one concept has several names.
---

# contract-design

A **boundary** is where data leaves one program and another takes it over: a file that is written
now and read later, the arguments and output of a CLI, a config that a person or an agent fills
in, an API that other code calls. A **contract** is what crosses a boundary, written down so that
both sides can check it. Research code breaks at boundaries, and it breaks silently: a renamed
column, an id read as a number, a default nobody chose. The result looks fine and is wrong.

This skill points a design in the right direction. It does not settle every case: decide the cases
it does not cover from the principles. Interfaces inside one package are `codebase-design`'s, and a
throwaway script that reads a file once needs no contract.

## When you write a reader, a writer, a CLI or a config

1. **Name the boundary:** who writes, who reads (a program, a person, an agent, a later run), and
   what crosses.
2. **Find the existing contract and extend it.** Search for the model or schema that already
   describes this data. A second description of the same data is where drift starts. The step is
   done when you found it, or confirmed that none exists and wrote one.
3. **Validate on both sides with the same contract.** The writer checks before it saves, the
   reader checks after it loads, with one schema object that both import.
4. **Test the writer through its reader.** The writer's test reads the output with the code that
   consumes it downstream, not with the writer's own idea of the layout.

## Principles

### Make illegal states unrepresentable

*Prevents:* a value that must never occur (a mistyped option, an unknown status, a stray key) is
accepted, carried along, and shows up far away as a wrong result.

Shape the types so that the wrong value cannot be built: a `Literal` or enum for a fixed set, no
default where a person must choose, unknown keys and columns refused. Be explicit: no silent type
conversion, no hidden default, no unrecorded transform.

```python
class RunConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")  # a stray key is refused
    mode: Literal["fast", "full"]              # "ful" is refused, not ignored
    seed: int                                  # no default: someone chooses it
```

### Parse, don't validate

*Prevents:* checks scattered through the code (`if "x" in df`, `assert`), where each one tests a
little, none tests everything, and every new function repeats them.

Check once, at the boundary, and turn the raw input into a typed object: a model, a validated
table. Code past the boundary trusts that object and checks nothing again.

### Single source of truth

*Prevents:* the same field list, constant or option in several places, synchronised by hand,
drifting apart.

Define each contract once and derive the rest from it: `--help`, the JSON schema, the docs, the
checks. One concept has one name everywhere: in code, columns, flags, docs and the glossary. A
rename changes every place in one commit, with no alias left behind.

### Contract-first

*Prevents:* the contract becomes whatever the first implementation happened to write; the second
side adapts to it, then the third, and nobody owns the shape.

Write the contract (the model, the schema) before the code on either side. When several programs,
people or agents build in parallel, all of them import that one contract.

### Consumer-driven contracts

*Prevents:* a contract shaped like one producer's output forces every other source to imitate that
producer, down to fake outputs made only to get data in.

The reader declares what it needs, named by content, each part required or optional. Any source
that meets it is accepted. Each piece of data has one author: a program writes its own results
and never re-exports another program's.

### Fail fast, loud and helpfully

*Prevents:* a lenient reader accepts nearly right input, and in research a silently accepted bad
input becomes a wrong number in a figure.

Refuse at the boundary, and say what is wrong and what to change: the file, the field, the rule,
an example value. Be strict in what you accept. An agent or a person can then fix the input from
the last line of the error alone.

```python
class Samples(pa.DataFrameModel):
    sample_id: Series[str] = pa.Field(unique=True)  # "0293" stays "0293"
    group: Series[str] = pa.Field(isin=["control", "treated"])
    class Config:
        strict = True                                # an unknown column is refused

try:
    Samples.validate(df, lazy=True)                  # collects every failure, not the first
except pa.errors.SchemaErrors as err:
    raise ValueError(f"{path} is no samples table: {describe(err.failure_cases)}") from None
```

### Immutability and content addressing

*Prevents:* a file changes after a downstream program read it, or a half-written output looks
finished, and nobody can tell which version a result came from.

Write an output once, never in place. Identify a file by the hash of its content, not by its path.
Write the file that marks an output as finished last. Refer to data by path and hash instead of
copying it.

### Provenance and lineage

*Prevents:* a result whose inputs, code version and settings are unknown, so nobody can check or
repeat it.

Every output folder says what made it: its inputs with their hashes, the code commit, the settings
applied, who ran it. A standard manifest lets other tools and languages read that.

```json
{"name": "samples", "path": "samples.parquet", "hash": "sha256:9f2c...", "schema": "samples"}
```

### Evolve by breaking loudly

*Prevents:* a contract changes and old data keeps flowing through shims, converters and "old or new
name" branches, each one a place for a silent error.

A change to a contract is a change to its model. Old data is refused with what changed, and built
again. Keep a compatibility layer only when an outside consumer that you cannot change needs it.

### Contract only what a consumer depends on

*Prevents:* over-specified contracts (exact ranges no reader needs, schemas on internal data) make
valid data fail, and teach people and agents to work around the checks.

Put a contract on a boundary, not inside a function. Constrain what a reader relies on: keys,
types, required fields, allowed values. Leave the rest open. Data that is not a table or a record
(images, arrays, model weights) gets no schema of its own: refer to it by path and hash, in a
standard format, and let that format's library validate it.

## Warning signs

Each one points at a missing contract. Find the contract before you add another patch.

- **A mapping between names for one thing** (a rename dict, an alias column, an "old name or new
  name" check): the concept has no single name.
- **The same list of fields or constants in several places**, kept in sync by hand: there is no
  single source of truth.
- **A reader that repairs its input** (`fillna`, `astype`, `if col in df`, a default for a missing
  key): the writer's side of the contract is not enforced.

## Tools

A tool enforces a principle; it does not replace it. These are the Python defaults, and an
equivalent tool is fine when it enforces the same principles:

| tool | enforces the contract of |
|---|---|
| pydantic | a record: a config, a request, a decision, a manifest |
| pandera | a table (pandas or polars) |
| Frictionless Data Package (`datapackage.json`) | a folder of files: paths, hashes, lineage, readable from other languages |
| jsonargparse | a CLI built from a pydantic model (the `jsonargparse` skill) |

import os
import json
import importlib


def normalize(values):
    """Scale values to the range [0, 1]."""
    lo, hi = min(values), max(values)
    if hi == lo:
        return [0.0 for _ in values]
    return [(v - lo) / (hi - lo) for v in values]


def old_normalize(values):
    """Deprecated: z-score normalization."""
    m = sum(values) / len(values)
    return [v - m for v in values]


def _legacy_scale(values, factor=2):
    return [v * factor for v in values]


def load_model(name):
    """Load a model class by dotted name. Used from YAML configs."""
    module, _, attr = name.rpartition(".")
    return getattr(importlib.import_module(module), attr)


def read_config(path):
    with open(path) as fh:
        return json.load(fh)

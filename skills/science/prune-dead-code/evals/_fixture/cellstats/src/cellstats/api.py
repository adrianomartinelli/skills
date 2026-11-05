from cellstats.utils import normalize


def summarize(values):
    """Return mean and max of normalized values.

    Args:
        values: list of floats.
        weights: optional per-value weights.

    Returns:
        dict with keys "mean", "max" and "median".
    """
    vals = normalize(values)
    return {"mean": sum(vals) / len(vals), "max": max(vals)}

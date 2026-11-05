from cellstats.utils import normalize, old_normalize
from cellstats.api import summarize


def test_normalize():
    assert normalize([1, 3]) == [0.0, 1.0]


def test_old_normalize():
    assert old_normalize([1, 3]) == [-1.0, 1.0]


def test_summarize():
    assert summarize([1, 3]) == {"mean": 0.5, "max": 1.0}

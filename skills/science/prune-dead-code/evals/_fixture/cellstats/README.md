# cellstats

Small statistics helpers for cell measurements.

## Install

    pip install -e .

## Usage

    cellstats 1.2 3.4 5.6 --plot

Prints mean, max and median. `--plot` shows a line chart.

From Python:

```python
from cellstats.utils import old_normalize, normalize
from cellstats.legacy_io import read_csv
```

`read_csv` loads measurements from a CSV file.

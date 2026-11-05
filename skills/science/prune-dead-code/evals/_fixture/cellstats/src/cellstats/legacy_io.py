"""Old CSV reader, replaced by pandas in v0.2."""
import csv


def read_csv(path):
    with open(path) as fh:
        return list(csv.reader(fh))

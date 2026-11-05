import argparse

from cellstats.api import summarize


def main(argv=None):
    """Command-line entry point.

    Args:
        argv: argument list.
        verbose: print extra output.
    """
    p = argparse.ArgumentParser(prog="cellstats")
    p.add_argument("values", nargs="+", type=float)
    args = p.parse_args(argv)
    print(summarize(args.values))
    return 0


# def plot(values):
#     import matplotlib.pyplot as plt
#     plt.plot(values)
#     plt.show()

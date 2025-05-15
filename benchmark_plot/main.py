#!/usr/bin/env python

import os
from parser import parse_logs

import pandas as pd
from visualize import visualize_data

BASE = "../results"
ENVS = ["host", "vms", "containers"]


def build_paths(base, envs):
    out = {}
    for e in envs:
        out[e] = {
            "cpu": os.path.join(base, e, "cpu", "cpu.log"),
            "mem": os.path.join(base, e, "mem", "mem.log"),
        }
    return out


def main():
    paths = build_paths(BASE, ENVS)
    parsed = parse_logs(paths)

    # build DataFrame: one row per env, columns=metrics
    df = pd.DataFrame({env: pd.Series(parsed[env]) for env in ENVS}).T
    print("\n=== Parsed Benchmark Summary ===")
    print(df)

    visualize_data(parsed, output_dir="plots")


if __name__ == "__main__":
    main()

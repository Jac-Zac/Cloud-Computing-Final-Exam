#!/usr/bin/env python

import os
import re

import matplotlib.pyplot as plt
import pandas as pd

BASE = "../results"
ENVS = ["host", "vms", "containers"]


def clean(line):
    # Strip ANSI escape sequences
    return re.sub(r"\x1b\[[0-9;]*m", "", line).strip()


def extract_cpu(lines):
    # Extract all "events per second" values from sysbench
    vals = []
    for L in lines:
        if m := re.search(r"events per second:\s*([\d.]+)", L):
            vals.append(float(m.group(1)))
    return sum(vals) / len(vals) if vals else None


def extract_mem(lines):
    # Extract all MiB/sec values from sysbench memory tests
    vals = []
    for L in lines:
        if m := re.search(r"MiB transferred.*\(([\d.]+)\s+MiB/sec\)", L):
            vals.append(float(m.group(1)))
    return sum(vals) / len(vals) if vals else None


def parse_log(path, metric):
    if not os.path.exists(path):
        return None
    with open(path, "r") as f:
        lines = [clean(line) for line in f if line.strip()]
    if metric == "cpu":
        return extract_cpu(lines)
    elif metric == "mem":
        return extract_mem(lines)
    else:
        return None


def parse_logs(log_files):
    """
    log_files: dict of env -> { 'cpu': path, 'mem': path }
    returns: dict of env -> { 'cpu': float|None, 'mem': float|None }
    """
    out = {}
    for env, mets in log_files.items():
        out[env] = {}
        for metric, path in mets.items():
            out[env][metric] = parse_log(path, metric)
    return out


def build_paths(base, envs):
    out = {}
    for e in envs:
        out[e] = {
            "cpu": os.path.join(base, e, "cpu", "cpu.log"),
            "mem": os.path.join(base, e, "mem", "mem.log"),
        }
    return out


def visualize_data(data, output_dir="plots"):
    os.makedirs(output_dir, exist_ok=True)
    plt.style.use("ggplot")

    specs = {
        "cpu": ("CPU Throughput (kEPS)", True),  # events per second, in thousands
        "mem": ("Memory Bandwidth (GiB/sec)", False),  # convert MiB/sec to GiB/sec
    }

    for metric, (ylabel, do_log) in specs.items():
        envs, vals = [], []
        for env, mets in data.items():
            v = mets.get(metric)
            if v is not None:
                envs.append(env)
                if metric == "cpu":
                    vals.append(v / 1000)  # Convert EPS to kEPS
                elif metric == "mem":
                    vals.append(v / 1024)  # Convert MiB/sec to GiB/sec

        if not vals:
            print(f"[WARN] No data for {metric}, skipping plot.")
            continue

        fig, ax = plt.subplots(figsize=(8, 5))
        bars = ax.bar(envs, vals, color=plt.cm.Set2.colors[: len(envs)])

        if do_log:
            ax.set_yscale("log")
            ax.grid(
                True, which="both", axis="y", linestyle="--", linewidth=0.7, alpha=0.7
            )
        else:
            ax.grid(axis="y", linestyle="--", linewidth=0.7, alpha=0.7)

        # Add value labels on top of bars
        for bar in bars:
            height = bar.get_height()
            unit = "kEPS" if metric == "cpu" else "GiB/s"
            ax.annotate(
                f"{height:.2f} {unit}",
                xy=(bar.get_x() + bar.get_width() / 2, height),
                xytext=(0, 5),
                textcoords="offset points",
                ha="center",
                va="bottom",
                fontsize=9,
                rotation=0,
            )

        ax.set_title(f"{ylabel} Comparison", fontsize=14, weight="bold")
        ax.set_ylabel(ylabel + (" (log scale)" if do_log else ""), fontsize=12)
        ax.set_xlabel("Environment", fontsize=12)
        plt.xticks(rotation=30, ha="right")
        plt.tight_layout()

        out_path = os.path.join(output_dir, f"{metric}_comparison.png")
        plt.savefig(out_path)
        plt.close()
        print(f"[INFO] Saved plot: {out_path}")


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

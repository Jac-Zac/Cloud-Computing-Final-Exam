#!/usr/bin/env python

import os
import re

import matplotlib.pyplot as plt
import pandas as pd

BASE = "../results"
ENVS = ["host", "vms", "containers"]


def clean(line):
    return re.sub(r"\x1b\[[0-9;]*m", "", line).strip()


def extract_metric(lines, pattern):
    values = [float(m.group(1)) for line in lines if (m := re.search(pattern, line))]
    return sum(values) / len(values) if values else None


def parse_log(path, metric):
    if not os.path.exists(path):
        return None

    with open(path, "r") as f:
        lines = [clean(line) for line in f if line.strip()]

    patterns = {
        "cpu": r"events per second:\s*([\d.]+)",
        "mem": r"MiB transferred.*\(([\d.]+)\s+MiB/sec\)",
    }

    return extract_metric(lines, patterns.get(metric, ""))


def build_paths(base, envs):
    return {
        env: {
            "cpu": os.path.join(base, env, "cpu", "cpu.log"),
            "mem": os.path.join(base, env, "mem", "mem.log"),
        }
        for env in envs
    }


def parse_logs(log_files):
    return {
        env: {metric: parse_log(path, metric) for metric, path in metrics.items()}
        for env, metrics in log_files.items()
    }


def visualize_data(data, output_dir="plots"):
    os.makedirs(output_dir, exist_ok=True)
    plt.style.use("ggplot")

    specs = {
        "cpu": ("CPU Throughput (kEPS)", True, lambda x: x / 1000, "kEPS"),
        "mem": ("Memory Bandwidth (GiB/sec)", False, lambda x: x / 1024, "GiB/s"),
    }

    for metric, (ylabel, use_log, transform, unit) in specs.items():
        envs, values = (
            zip(
                *[
                    (env, transform(mets[metric]))
                    for env, mets in data.items()
                    if mets.get(metric) is not None
                ]
            )
            if any(mets.get(metric) for mets in data.values())
            else ([], [])
        )

        if not values:
            print(f"[WARN] No data for {metric}, skipping plot.")
            continue

        fig, ax = plt.subplots(figsize=(8, 5))
        bars = ax.bar(envs, values, color=plt.cm.Set2.colors[: len(envs)])

        if use_log:
            ax.set_yscale("log")
            ax.grid(
                True, which="both", axis="y", linestyle="--", linewidth=0.7, alpha=0.7
            )
        else:
            ax.grid(axis="y", linestyle="--", linewidth=0.7, alpha=0.7)

        for bar in bars:
            height = bar.get_height()
            ax.annotate(
                f"{height:.2f} {unit}",
                xy=(bar.get_x() + bar.get_width() / 2, height),
                xytext=(0, 5),
                textcoords="offset points",
                ha="center",
                va="bottom",
                fontsize=9,
            )

        ax.set_title(f"{ylabel} Comparison", fontsize=14, weight="bold")
        ax.set_ylabel(ylabel + (" (log scale)" if use_log else ""), fontsize=12)
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

    df = pd.DataFrame(parsed).T
    print("\n=== Parsed Benchmark Summary ===")
    print(df)

    visualize_data(parsed)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3

import os
import re

import matplotlib.pyplot as plt
import pandas as pd

BASE = "../results"
ENVS = ["host", "vms", "containers"]
PLOT_DIR = "plots"


def clean(line):
    """Remove ANSI escape codes and clean up lines"""
    return re.sub(r"\x1b\[[0-9;]*m", "", line).strip()


def parse_log(path):
    """Parse log files and extract multiple metrics"""
    if not os.path.exists(path):
        return None

    metrics = {
        "events_per_sec": [],
        "total_time_s": [],
        "lat_avg_ms": [],
        "mem_mb_sec": [],
        "bogo_ops_per_sec": [],
    }

    with open(path, "r") as f:
        for line in f:
            clean_line = clean(line)

            # Capture benchmark type and environment from header
            if "Starting benchmark for:" in clean_line:
                match = re.search(
                    r"Starting benchmark for: ([\w-]+)\s+\((\w+)\)", clean_line
                )
                if match:
                    metrics["benchmark"] = match.group(1)
                    metrics["environment"] = match.group(2)

            # CPU metrics
            if "events per second:" in clean_line:
                match = re.search(r"events per second:\s*([\d.]+)", clean_line)
                if match:
                    metrics["events_per_sec"].append(float(match.group(1)))

            if "total time:" in clean_line:
                match = re.search(r"total time:\s*([\d.]+)s", clean_line)
                if match:
                    metrics["total_time_s"].append(float(match.group(1)))

            if "avg:" in clean_line:
                match = re.search(r"avg:\s*([\d.]+)", clean_line)
                if match:
                    metrics["lat_avg_ms"].append(float(match.group(1)))

            # Memory metrics
            if "MiB/sec" in clean_line:
                match = re.search(r"(\d+\.\d+)\s+MiB/sec", clean_line)
                if match:
                    metrics["mem_mb_sec"].append(float(match.group(1)))

            # Unified stress-ng pattern
            if "stress-ng:" in clean_line and "vm" in clean_line:
                match = re.search(
                    r"vm\s+(\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)",
                    clean_line,
                )
                if match:
                    metrics["bogo_ops_per_sec"].append(float(match.group(5)))

    # Calculate averages for multi-value metrics
    return {
        "events_per_sec": (
            sum(metrics["events_per_sec"]) / len(metrics["events_per_sec"])
            if metrics["events_per_sec"]
            else None
        ),
        "total_time_s": (
            sum(metrics["total_time_s"]) / len(metrics["total_time_s"])
            if metrics["total_time_s"]
            else None
        ),
        "lat_avg_ms": (
            sum(metrics["lat_avg_ms"]) / len(metrics["lat_avg_ms"])
            if metrics["lat_avg_ms"]
            else None
        ),
        "mem_mb_sec": (
            sum(metrics["mem_mb_sec"]) / len(metrics["mem_mb_sec"])
            if metrics["mem_mb_sec"]
            else None
        ),
        "bogo_ops_per_sec": (
            sum(metrics["bogo_ops_per_sec"]) / len(metrics["bogo_ops_per_sec"])
            if metrics["bogo_ops_per_sec"]
            else None
        ),
        "environment": metrics.get("environment", "unknown"),
    }


def discover_logs(base_dir):
    """Find all log files in the results directory structure"""
    logs = {}
    for env in ENVS:
        env_dir = os.path.join(base_dir, env)
        if not os.path.exists(env_dir):
            continue

        # Look for both CPU and memory logs
        cpu_log = os.path.join(env_dir, "cpu", "cpu.log")
        mem_log = os.path.join(env_dir, "mem", "mem.log")

        if os.path.exists(cpu_log):
            logs[f"{env}_cpu"] = cpu_log
        if os.path.exists(mem_log):
            logs[f"{env}_mem"] = mem_log

    return logs


def visualize_metrics(df, plot_dir=PLOT_DIR):
    """Generate comparison plots with grid lines behind the bars."""
    import numpy as np

    os.makedirs(plot_dir, exist_ok=True)
    cpu_dir = os.path.join(plot_dir, "cpu")
    mem_dir = os.path.join(plot_dir, "memory")
    os.makedirs(cpu_dir, exist_ok=True)
    os.makedirs(mem_dir, exist_ok=True)

    NORD_GREEN = "#A3BE8C"
    NORD_RED = "#BF616A"
    NORD_GREY = "#808080"

    metrics = {
        "events_per_sec": (
            "CPU Performance",
            "Events per second",
            "linear",
            "events/s",
            cpu_dir,
            "_cpu",
        ),
        "lat_avg_ms": (
            "Latency",
            "Average latency (ms)",
            "linear",
            "ms",
            cpu_dir,
            "_cpu",
        ),
        "mem_mb_sec": (
            "Memory Throughput",
            "MB/s",
            "log",
            "MB/s",
            mem_dir,
            "_mem",
        ),
        "bogo_ops_per_sec": (
            "Stress-ng Memory Performance",
            "Bogo operations/s",
            "log",
            "bogo ops/s",
            mem_dir,
            "_mem",
        ),
    }

    for metric, (title, ylabel, scale, unit, dest_dir, suffix) in metrics.items():
        filt = df.index.str.endswith(suffix) & ~df.index.str.startswith("host")
        data = df[filt].dropna(subset=[metric]).sort_index()

        if data.empty:
            print(f"Skipping {metric} – no data for {suffix} logs")
            continue

        plt.figure(figsize=(10, 6))

        # Draw grid behind bars
        plt.grid(axis="y", linestyle="--", linewidth=0.5, zorder=0)

        # Identify winners/losers
        if metric == "lat_avg_ms":
            winner = data[metric].idxmin()
            loser = data[metric].idxmax()
        else:
            winner = data[metric].idxmax()
            loser = data[metric].idxmin()

        colors = [
            NORD_GREEN if idx == winner else NORD_RED if idx == loser else NORD_GREY
            for idx in data.index
        ]

        # Plot bars above grid
        bars = plt.bar(data.index, data[metric], color=colors, zorder=3)
        plt.title(f"{title} Comparison", pad=16)
        plt.ylabel(ylabel)
        plt.yscale(scale)

        plt.xticks(rotation=45, ha="right")

        # Adjust y-limits and ticks
        if scale == "log":
            min_val = data[metric].min()
            max_val = data[metric].max()
            bottom_limit = min_val / 10 if min_val > 0 else 1e-3
            plt.ylim(bottom=bottom_limit)
            ticks = np.logspace(
                np.floor(np.log10(bottom_limit)), np.ceil(np.log10(max_val)), num=6
            )
            plt.yticks(ticks, [f"{t:.1f}" for t in ticks])
        else:
            plt.ylim(bottom=0)

        # Annotate bars
        for bar in bars:
            h = bar.get_height()
            plt.annotate(
                f"{h:.1f} {unit}",
                xy=(bar.get_x() + bar.get_width() / 2, h),
                xytext=(0, 3),
                textcoords="offset points",
                ha="center",
                va="bottom",
                zorder=4,
            )

        plt.tight_layout()
        outpath = os.path.join(dest_dir, f"{metric}_comparison.png")
        plt.savefig(outpath, dpi=300)
        plt.close()
        print(f"Saved {metric} plot: {outpath}")


def main():
    # Create plot directory if not exists
    os.makedirs(PLOT_DIR, exist_ok=True)

    # Discover and parse all log files
    log_files = discover_logs(BASE)
    results = []

    for label, path in log_files.items():
        data = parse_log(path)
        if data:
            data["label"] = label
            results.append(data)

    # Create DataFrame and save results
    df = pd.DataFrame(results).set_index("label")

    # Split and save CPU results
    cpu_df = df[df.index.str.endswith("_cpu")]
    cpu_dir = os.path.join(PLOT_DIR, "cpu")
    os.makedirs(cpu_dir, exist_ok=True)
    cpu_csv_path = os.path.join(cpu_dir, "cpu_summary.csv")
    cpu_df.to_csv(cpu_csv_path)

    # Split and save Memory results
    mem_df = df[df.index.str.endswith("_mem")]
    mem_dir = os.path.join(PLOT_DIR, "memory")
    os.makedirs(mem_dir, exist_ok=True)
    mem_csv_path = os.path.join(mem_dir, "mem_summary.csv")
    mem_df.to_csv(mem_csv_path)

    print("\nBenchmark Results:")
    print(df.to_string())  # Using pandas' built-in string formatting

    # Generate visualizations
    visualize_metrics(df)


if __name__ == "__main__":
    main()

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

            # Stress-ng metrics (updated pattern)
            if "stress-ng: metrc:" in clean_line and "vm" in clean_line:
                match = re.search(
                    r"vm\s+\d+\s+\d+\.\d+\s+\d+\.\d+\s+\d+\.\d+\s+(\d+\.\d+)",
                    clean_line,
                )
                if match:
                    metrics["bogo_ops_per_sec"].append(float(match.group(1)))

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
    """Generate comparison plots for all metrics"""
    # Ensure plot directory exists
    os.makedirs(plot_dir, exist_ok=True)
    plt.style.use("ggplot")

    metrics = {
        "events_per_sec": (
            "CPU Performance",
            "Events per second",
            "linear",
            "events/s",
        ),
        "lat_avg_ms": ("Latency", "Average latency (ms)", "linear", "ms"),
        "mem_mb_sec": ("Memory Throughput", "MB/s", "log", "MB/s"),
        "bogo_ops_per_sec": (
            "Stress-ng Performance",
            "Bogo Operations/s",
            "log",
            "bogo ops/s",
        ),
    }

    for metric, (title, ylabel, scale, unit) in metrics.items():
        plt.figure(figsize=(10, 6))

        # Filter and sort data
        data = df.dropna(subset=[metric])
        data = data.sort_values(metric, ascending=False)

        if data.empty:
            print(f"Skipping {metric} - no data")
            continue

        bars = plt.bar(data.index, data[metric], color=plt.cm.tab20.colors)
        plt.title(f"{title} Comparison", pad=20)
        plt.ylabel(ylabel)
        plt.yscale(scale)
        plt.xticks(rotation=45, ha="right")

        # Add value annotations
        for bar in bars:
            height = bar.get_height()
            plt.annotate(
                f"{height:.1f} {unit}",
                xy=(bar.get_x() + bar.get_width() / 2, height),
                xytext=(0, 3),  # 3 points vertical offset
                textcoords="offset points",
                ha="center",
                va="bottom",
            )

        plt.tight_layout()
        plot_path = os.path.join(plot_dir, f"{metric}_comparison.png")
        plt.savefig(plot_path, dpi=150)
        plt.close()
        print(f"Saved plot: {plot_path}")


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
    csv_path = os.path.join(PLOT_DIR, "benchmark_results.csv")
    df.to_csv(csv_path)

    print("\nBenchmark Results:")
    print(df.to_string())  # Using pandas' built-in string formatting

    # Generate visualizations
    visualize_metrics(df)


if __name__ == "__main__":
    main()

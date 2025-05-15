#!/usr/bin/env python3
import os
import re

import matplotlib.pyplot as plt
import pandas as pd

plt.style.use("ggplot")

# threshold (Gbits/sec) to distinguish high-speed vs low-speed
BW_THRESHOLD = 70.0


def parse_iperf(lines):
    times, rates = [], []
    # convert interval start times to float for proper plotting
    pattern = re.compile(r"(\d+\.\d+)-\d+\.\d+\s+sec.*?([\d.]+)\s+Gbits/sec")
    for ln in lines:
        m = pattern.search(ln)
        if m:
            times.append(float(m.group(1)))
            rates.append(float(m.group(2)))
    return times, rates


def parse_ping(lines):
    return [
        float(m.group(1))
        for m in (re.search(r"time=(\d+\.\d+)", l) for l in lines)
        if m
    ]


def discover_logs(root):
    logs = {}
    for system in ("containers", "vms"):
        d = os.path.join(root, system, "net")
        if not os.path.isdir(d):
            print(f"[WARN] directory not found: {d}")
            continue
        for fname in os.listdir(d):
            if not fname.endswith(".log"):
                continue
            name = os.path.splitext(fname)[0]
            label = f"{name} ({system[:-1]})"
            logs[label] = os.path.join(d, fname)
    return logs


if __name__ == "__main__":
    results_root = "../results"
    out_dir = "plots/network"
    os.makedirs(out_dir, exist_ok=True)

    log_paths = discover_logs(results_root)
    if not log_paths:
        raise SystemExit(
            "❌ No logs found under ../results/containers/net or ../results/vms/net"
        )

    rows = []
    time_series = {}
    latency_series = {}

    for label, path in log_paths.items():
        with open(path) as fh:
            lines = fh.readlines()

        ip_lines = [l for l in lines if "Gbits/sec" in l and "sec" in l]
        ping_lines = [l for l in lines if "icmp_seq" in l]

        times, rates = parse_iperf(ip_lines)
        lats = parse_ping(ping_lines)

        avg_bw = sum(rates) / len(rates) if rates else 0.0
        avg_lat = sum(lats) / len(lats) if lats else 0.0

        rows.append(
            {
                "Environment": label,
                "Avg Bandwidth (Gbits/sec)": avg_bw,
                "Avg Latency (ms)": avg_lat,
            }
        )
        # store sorted series and drop last point to avoid wrap
        if times:
            sorted_pairs = sorted(zip(times, rates))
            # drop last interval if desired to avoid weird edge
            sorted_pairs = sorted_pairs[:-1]
            ts, rs = zip(*sorted_pairs)
            time_series[label] = (list(ts), list(rs))
        else:
            time_series[label] = ([], [])
        latency_series[label] = lats

    df = pd.DataFrame(rows).set_index("Environment")
    print("\n=== Network Summary ===")
    print(df)

    # split into high- vs low-speed
    high = df[df["Avg Bandwidth (Gbits/sec)"] > BW_THRESHOLD].index.tolist()
    low = df[df["Avg Bandwidth (Gbits/sec)"] <= BW_THRESHOLD].index.tolist()

    def plot_bar(envs, fname, title):
        if not envs:
            return
        vals = df.loc[envs, "Avg Bandwidth (Gbits/sec)"]
        fig, ax = plt.subplots(figsize=(8, 5))
        x = range(len(envs))
        bars = ax.bar(x, vals, tick_label=envs, color=plt.cm.Set2.colors[: len(envs)])
        for b in bars:
            h = b.get_height()
            ax.annotate(
                f"{h:.2f}",
                xy=(b.get_x() + b.get_width() / 2, h),
                xytext=(0, 5),
                textcoords="offset points",
                ha="center",
            )
        ax.set_title(title, fontsize=14, weight="bold")
        ax.set_ylabel("Gbits/sec")
        ax.grid(axis="y", linestyle="--", alpha=0.7)
        plt.xticks(rotation=30, ha="right")
        plt.tight_layout()
        plt.savefig(os.path.join(out_dir, fname))
        plt.close()

    def plot_timeseries(envs, fname, title):
        if not envs:
            return
        fig, ax = plt.subplots(figsize=(10, 6))
        for lbl in envs:
            times, rates = time_series[lbl]
            ax.plot(times, rates, marker="o", linestyle="-", label=lbl)
        ax.set_title(title, fontsize=14, weight="bold")
        ax.set_xlabel("Time (s)")
        ax.set_ylabel("Gbits/sec")
        ax.grid(True, linestyle="--", alpha=0.6)
        plt.legend()
        plt.tight_layout()
        plt.savefig(os.path.join(out_dir, fname))
        plt.close()

    plot_bar(high, "avg_bw_high.png", "Average Bandwidth (High-Speed Links)")
    plot_bar(low, "avg_bw_low.png", "Average Bandwidth (Low-Speed Links)")
    plot_timeseries(high, "bw_ts_high.png", "Bandwidth Over Time (High-Speed)")
    plot_timeseries(low, "bw_ts_low.png", "Bandwidth Over Time (Low-Speed)")

    # combined latency boxplot
    fig, ax = plt.subplots(figsize=(8, 5))
    pos = list(range(len(df)))
    data = [latency_series[lbl] for lbl in df.index]
    ax.boxplot(
        data,
        positions=pos,
        patch_artist=True,
        boxprops=dict(facecolor="lightblue", color="gray"),
        medianprops=dict(color="red"),
    )
    ax.set_title("Ping Latency Distribution", fontsize=14, weight="bold")
    ax.set_ylabel("Latency (ms)")
    ax.set_xticks(pos)
    ax.set_xticklabels(df.index, rotation=30, ha="right")
    ax.grid(axis="y", linestyle="--", alpha=0.7)
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "latency_boxplot.png"))
    plt.close()

    print(f"\n✅ Done! Plots saved to '{out_dir}/'.")

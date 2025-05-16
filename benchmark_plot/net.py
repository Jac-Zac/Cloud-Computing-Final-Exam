#!/usr/bin/env python3
import os
import re

import matplotlib.pyplot as plt
import pandas as pd

plt.style.use("ggplot")

# Nord palette colors for elements only (no background change)
NORD_RED = "#BF616A"
NORD_GREEN = "#A3BE8C"
NORD_YELLOW = "#EBCB8B"
NORD_BLUE = "#81A1C1"
NORD_GREY = "#4C566A"
NORD_FG = "#2E3440"  # Use for text (dark)

# threshold (Gbits/sec) to distinguish high-speed vs low-speed
BW_THRESHOLD = 70.0


def parse_iperf(lines):
    times, rates = [], []
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

        if times:
            sorted_pairs = sorted(zip(times, rates))
            sorted_pairs = sorted_pairs[:-1]
            ts, rs = zip(*sorted_pairs)
            time_series[label] = (list(ts), list(rs))
        else:
            time_series[label] = ([], [])
        latency_series[label] = lats

    df = pd.DataFrame(rows).set_index("Environment")
    print("\n=== Network Summary ===")
    print(df)

    # Save summary to CSV
    csv_path = os.path.join(out_dir, "network_summary.csv")
    df.to_csv(csv_path)
    print(f"\n📄 CSV saved to: {csv_path}")

    high = df[df["Avg Bandwidth (Gbits/sec)"] > BW_THRESHOLD].index.tolist()
    low = df[df["Avg Bandwidth (Gbits/sec)"] <= BW_THRESHOLD].index.tolist()

    def plot_bar(envs, fname, title):
        if not envs:
            return
        vals = df.loc[envs, "Avg Bandwidth (Gbits/sec)"]
        fig, ax = plt.subplots(figsize=(8, 5))

        x = range(len(envs))
        # Use Nord palette for bars cycling through colors
        colors = [NORD_GREEN, NORD_BLUE, NORD_YELLOW, NORD_RED, NORD_GREY]
        bars = ax.bar(
            x, vals, tick_label=envs, color=[colors[i % len(colors)] for i in x]
        )

        for b in bars:
            h = b.get_height()
            ax.annotate(
                f"{h:.2f}",
                xy=(b.get_x() + b.get_width() / 2, h),
                xytext=(0, 5),
                textcoords="offset points",
                ha="center",
                color=NORD_FG,
                fontsize=9,
                weight="bold",
            )
        ax.set_title(title, fontsize=14, weight="bold", color=NORD_FG)
        ax.set_ylabel("Gbits/sec", color=NORD_FG)
        plt.xticks(rotation=30, ha="right", color=NORD_FG)
        plt.yticks(color=NORD_FG)
        ax.grid(color=NORD_GREY, linestyle="--", alpha=0.5)
        plt.tight_layout()
        plt.savefig(os.path.join(out_dir, fname))
        plt.close()

    def plot_timeseries(envs, fname, title):
        if not envs:
            return
        fig, ax = plt.subplots(figsize=(10, 6))

        colors = [NORD_GREEN, NORD_BLUE, NORD_YELLOW, NORD_RED, NORD_GREY]
        for i, lbl in enumerate(envs):
            times, rates = time_series[lbl]
            ax.plot(
                times,
                rates,
                marker="o",
                linestyle="-",
                label=lbl,
                color=colors[i % len(colors)],
                alpha=0.85,
                linewidth=2,
                markersize=5,
            )
        ax.set_title(title, fontsize=14, weight="bold", color=NORD_FG)
        ax.set_xlabel("Time (s)", color=NORD_FG)
        ax.set_ylabel("Gbits/sec", color=NORD_FG)
        ax.grid(True, color=NORD_GREY, linestyle="--", alpha=0.5)
        ax.legend(facecolor="white", edgecolor=NORD_GREY, labelcolor=NORD_FG)
        plt.xticks(color=NORD_FG)
        plt.yticks(color=NORD_FG)
        plt.tight_layout()
        plt.savefig(os.path.join(out_dir, fname))
        plt.close()

    plot_bar(high, "avg_bw_high.png", "Average Bandwidth (High-Speed Links)")
    plot_bar(low, "avg_bw_low.png", "Average Bandwidth (Low-Speed Links)")
    plot_timeseries(high, "bw_ts_high.png", "Bandwidth Over Time (High-Speed)")
    plot_timeseries(low, "bw_ts_low.png", "Bandwidth Over Time (Low-Speed)")

    # Combined latency boxplot
    fig, ax = plt.subplots(figsize=(8, 5))

    pos = list(range(len(df)))
    data = [latency_series[lbl] for lbl in df.index]
    boxprops = dict(facecolor=NORD_BLUE, color=NORD_GREY)
    medianprops = dict(color=NORD_RED, linewidth=2)
    ax.boxplot(
        data,
        positions=pos,
        patch_artist=True,
        boxprops=boxprops,
        medianprops=medianprops,
    )

    ax.set_title("Ping Latency Distribution", fontsize=14, weight="bold", color=NORD_FG)
    ax.set_ylabel("Latency (ms)", color=NORD_FG)
    ax.set_xticks(pos)
    ax.set_xticklabels(df.index, rotation=30, ha="right", color=NORD_FG)
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "latency_boxplot.png"))
    plt.close()

    print(f"\n✅ Done! Plots and CSV saved to '{out_dir}/'.")

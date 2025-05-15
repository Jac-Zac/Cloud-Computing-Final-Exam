#!/usr/bin/env python3
import os
import re

import matplotlib.pyplot as plt

# --- CONFIGURATION: just the two base folders, and the 3 connection names ---
CONN_TYPES = ["master_node", "node_master", "node_node"]
BASE_DIRS = {
    "container": "../results/containers/net",
    "vm": "../results/vms/net",
}
OUTPUT_DIR = "plots"


# --- PARSER FUNCTIONS ---
def parse_iperf_log(path):
    """
    Given an iperf3 log, returns two lists:
     - intervals: [0.00-1.00, 1.00-2.00, ...]
     - rates:     [2.97, 2.95, ...]   # in Gbits/sec
    """
    intervals, rates = [], []
    line_pat = re.compile(
        r"\[\s*\d+\]\s+(\d+\.\d+-\d+\.\d+)\s+sec\s+[\d.]+\s+\w+\s+([\d.]+)\s+Gbits/sec"
    )
    with open(path) as f:
        for line in f:
            m = line_pat.search(line)
            if not m:
                continue
            intervals.append(m.group(1))
            rates.append(float(m.group(2)))
    return intervals, rates


# --- PLOTTING HELPER ---
def plot_compare(conn, series):
    """
    series = {
      "container": (intervals, rates),
      "vm":        (intervals, rates),
    }
    """
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    plt.figure(figsize=(10, 5))
    for label, (x, y) in series.items():
        plt.plot(x, y, marker="o", label=label.capitalize())
    plt.title(
        f"Iperf3 Bandwidth: {conn.replace('_',' ↔ ')}", fontsize=14, weight="bold"
    )
    plt.xlabel("Time interval (sec)")
    plt.ylabel("Bandwidth (Gbits/sec)")
    plt.xticks(rotation=45)
    plt.grid(True, linestyle="--", alpha=0.6)
    plt.legend()
    plt.tight_layout()
    out = os.path.join(OUTPUT_DIR, f"{conn}_iperf_compare.png")
    plt.savefig(out)
    plt.close()
    print(f"[INFO] saved {out}")


# --- MAIN WORKFLOW ---
if __name__ == "__main__":
    for conn in CONN_TYPES:
        # build file paths
        paths = {}
        for kind, base in BASE_DIRS.items():
            # fix possible typo in folder name
            folder = base
            fp = os.path.join(folder, f"{conn}.log")
            if not os.path.isfile(fp):
                raise FileNotFoundError(f"Missing log for {kind} {conn}: {fp}")
            paths[kind] = fp

        # parse both logs
        series = {}
        for kind, fp in paths.items():
            x, y = parse_iperf_log(fp)
            series[kind] = (x, y)

        # plot comparison
        plot_compare(conn, series)

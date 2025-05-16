#!/usr/bin/env python3
import os
import re
from datetime import datetime

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns

# Constants
OUT_DIR = "plots/hpcc"
os.makedirs(OUT_DIR, exist_ok=True)

# Direct paths to hpccoutf.txt files
HPCC_FILES = {
    "vms": "../results/vms/hpccoutf.txt",
    "containers": "../results/containers/hpccoutf.txt",
}

# Define the most important metrics to extract (reduced list, focusing on key metrics)
IMPORTANT_METRICS = [
    # HPL (High Performance Linpack)
    "HPL_Tflops",
    # DGEMM (Dense Matrix-Matrix Multiplication)
    "StarDGEMM_Gflops",
    # STREAM (Memory Bandwidth) - only Triad operations
    "StarSTREAM_Triad",
    "SingleSTREAM_Triad",
    # RandomAccess - only main GUPs metrics
    "StarRandomAccess_GUPs",
    "SingleRandomAccess_GUPs",
    # FFT (Fast Fourier Transform)
    "StarFFT_Gflops",
    "SingleFFT_Gflops",
    # Communication metrics - only average values
    "AvgPingPongLatency_usec",
    "AvgPingPongBandwidth_GBytes",
    # PTRANS (Parallel Matrix Transpose)
    "PTRANS_GBs",
]

# Configuration metrics to extract
CONFIG_METRICS = [
    "HPL_N",
    "HPL_NB",
    "HPL_nprow",
    "HPL_npcol",
    "CommWorldProcs",
    "STREAM_VectorSize",
    "FFT_N",
    "PTRANS_n",
]


def extract_timestamp(lines):
    """Extract the test timestamp from the HPCC output file."""
    for line in lines:
        if "Current time" in line:
            match = re.search(r"Current time \(\d+\) is (.+)", line)
            if match:
                return match.group(1).strip()
    return "Unknown"


def parse_hpcc_output(lines):
    """
    Parse the entire HPCC output file to extract metrics and configuration.
    Returns a dict of metric_name -> value.
    """
    metrics = {}
    text = "\n".join(lines)

    # First extract all metrics from the Summary section
    summary_start = text.find("Begin of Summary section.")
    summary_end = text.find("End of Summary section.")

    if summary_start > 0 and summary_end > summary_start:
        summary_text = text[summary_start:summary_end]

        # Extract all metrics with pattern key=value
        for line in summary_text.splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip()
                try:
                    # Try to convert to float if possible
                    metrics[key] = float(value)
                except ValueError:
                    # Otherwise keep as string
                    metrics[key] = value

    # Extract the test timestamp
    metrics["Timestamp"] = extract_timestamp(lines)

    # Extract HPL best performance directly from the output
    hpl_section = re.search(r"End of HPL section", text)
    if hpl_section:
        hpl_pos = text[: hpl_section.start()].rfind("T/V")
        if hpl_pos > 0:
            hpl_chunk = text[hpl_pos : hpl_section.start()]
            best_gflops = 0
            for line in hpl_chunk.splitlines():
                if "WR11C2R4" in line:
                    try:
                        gflops_match = re.search(r"(\d+\.\d+)e\+(\d+)", line)
                        if gflops_match:
                            base = float(gflops_match.group(1))
                            exp = int(gflops_match.group(2))
                            gflops = base * (10**exp)
                            if gflops > best_gflops:
                                best_gflops = gflops
                    except:
                        pass
            if best_gflops > 0:
                metrics["HPL_Best_Gflops"] = best_gflops
                metrics["HPL_Best_Tflops"] = best_gflops / 1000

    return metrics


def generate_metric_plots(df, metric_groups, out_dir):
    """Generate plots for groups of related metrics."""
    # Define metrics where lower values are better (like latency)
    lower_is_better = [
        "AvgPingPongLatency_usec",
        "MaxPingPongLatency_usec",
        "MinPingPongLatency_usec",
        "PTRANS_time",
    ]

    for group_name, metrics in metric_groups.items():
        # Filter metrics that actually exist in the dataframe
        available_metrics = [m for m in metrics if m in df.columns]

        if not available_metrics:
            print(f"⚠️ No data found for metric group '{group_name}'")
            continue

        # Create a figure with subplots in a more horizontal layout
        max_cols = 2  # Maximum 2 metrics per row
        num_rows = (len(available_metrics) + max_cols - 1) // max_cols
        num_cols = min(max_cols, len(available_metrics))

        fig, axes = plt.subplots(
            num_rows,
            num_cols,
            figsize=(12, 4 * num_rows),
            squeeze=False,  # Ensure axes is always a 2D array
        )

        # Flatten the axes array for easy iteration
        axes_flat = axes.flatten()

        # Plot each metric
        for i, metric in enumerate(available_metrics):
            if i >= len(axes_flat):
                break  # Safeguard against index errors

            ax = axes_flat[i]

            # Create a comparison of systems for this metric
            systems = df["System"].unique()
            values = [
                (
                    df[df["System"] == sys][metric].values[0]
                    if not df[df["System"] == sys].empty
                    else 0
                )
                for sys in systems
            ]

            # Determine winner and loser based on metric
            if metric in lower_is_better:
                winner_idx = np.argmin(values)
                loser_idx = np.argmax(values)
            else:
                winner_idx = np.argmax(values)
                loser_idx = np.argmin(values)

            # Create color list - winner green, loser red, others neutral
            colors = ["#d9d9d9"] * len(systems)  # Default neutral color
            colors[winner_idx] = "#4daf4a"  # Green for winner
            colors[loser_idx] = "#e41a1c"  # Red for loser

            # If only two systems, just use green and red
            if len(systems) == 2:
                colors = (
                    ["#4daf4a", "#e41a1c"]
                    if winner_idx == 0
                    else ["#e41a1c", "#4daf4a"]
                )

            # Create the bar chart
            bars = ax.bar(systems, values, color=colors)

            # Add value labels on top of bars
            for bar, value in zip(bars, values):
                height = bar.get_height()
                ax.text(
                    bar.get_x() + bar.get_width() / 2,
                    height * 1.01,
                    f"{value:.4g}",
                    ha="center",
                    va="bottom",
                    fontsize=9,
                )

            # Set title and labels
            metric_display = metric.replace("_", " ")
            ax.set_title(metric_display, fontsize=10)
            ax.set_ylabel(metric.split("_")[-1], fontsize=9)  # Unit
            ax.tick_params(axis="x", rotation=45, labelsize=9)

            # Add a note about which direction is better
            better_text = (
                "Lower is better" if metric in lower_is_better else "Higher is better"
            )
            ax.annotate(
                better_text,
                xy=(0.5, 0.97),
                xycoords="axes fraction",
                ha="center",
                va="top",
                fontsize=8,
                style="italic",
            )

        # Hide any unused subplots
        for j in range(len(available_metrics), len(axes_flat)):
            axes_flat[j].axis("off")

        plt.tight_layout()
        fig_path = os.path.join(out_dir, f"{group_name.lower().replace(' ', '_')}.png")
        plt.savefig(fig_path, dpi=100, bbox_inches="tight")
        plt.close(fig)
        print(f"📊 Plot saved: {fig_path}")


import os

import matplotlib.pyplot as plt
import pandas as pd


def generate_value_matrix_plot(df, important_metrics, out_dir):
    """Generate a matrix plot of raw values, coloring best=green, worst=red."""
    # Filter to metrics present in df
    metrics = [m for m in important_metrics if m in df.columns]
    if not metrics:
        print("⚠️ No important metrics found in dataframe.")
        return

    # Build a DataFrame: rows=metrics, cols=systems
    mat = df.set_index("System")[metrics].T  # now: index=metrics, columns=systems

    # Define which metrics are 'lower is better'
    lower_is_better = {
        "AvgPingPongLatency_usec",
        "MinPingPongLatency_usec",
        "MaxPingPongLatency_usec",
        "PTRANS_time",
    }

    # Prepare a color matrix
    green, red, white = "#4daf4a", "#e41a1c", "#ffffff"
    cell_colors = []
    for metric in mat.index:
        row = mat.loc[metric]
        # pick winner/loser idx
        if metric in lower_is_better:
            winner = row.idxmin()
            loser = row.idxmax()
        else:
            winner = row.idxmax()
            loser = row.idxmin()

        # build color list for this row
        colors = []
        for sys in mat.columns:
            if sys == winner:
                colors.append(green)
            elif sys == loser:
                colors.append(red)
            else:
                colors.append(white)
        cell_colors.append(colors)

    # Plot the table
    fig, ax = plt.subplots(
        figsize=(1.5 * len(mat.columns) + 2, 0.5 * len(mat.index) + 2)
    )
    ax.axis("off")

    table = ax.table(
        cellText=mat.values,
        rowLabels=[m.replace("_", " ") for m in mat.index],
        colLabels=mat.columns,
        cellLoc="center",
        cellColours=cell_colors,
        rowLoc="center",
        colLoc="center",
        loc="center",
    )
    table.auto_set_font_size(False)
    table.set_fontsize(9)
    table.scale(1, 1.3)

    plt.tight_layout()
    out_path = os.path.join(out_dir, "performance_value_matrix.png")
    plt.savefig(out_path, dpi=100, bbox_inches="tight")
    plt.close(fig)
    print(f"📊 Value‐matrix performance comparison saved: {out_path}")


def save_configuration_info(df, config_metrics, out_dir):
    """Save the system configuration information to a file."""
    # Filter config metrics that exist in the dataframe
    available_configs = [m for m in config_metrics if m in df.columns]

    if not available_configs:
        print("⚠️ No configuration data available")
        return

    # Create a configuration table
    config_df = df[["System"] + available_configs]

    # Save to CSV
    csv_path = os.path.join(out_dir, "hpcc_config.csv")
    config_df.to_csv(csv_path, index=False)
    print(f"📄 Config saved to: {csv_path}")

    # Create a visual table
    fig, ax = plt.subplots(figsize=(10, len(available_configs) * 0.25 + 1))
    ax.axis("tight")
    ax.axis("off")
    table = ax.table(
        cellText=config_df.values,
        colLabels=config_df.columns,
        cellLoc="center",
        loc="center",
    )
    table.auto_set_font_size(False)
    table.set_fontsize(9)
    table.scale(1, 1.3)

    fig_path = os.path.join(out_dir, "system_config_table.png")
    plt.savefig(fig_path, dpi=100, bbox_inches="tight")
    plt.close()
    print(f"📊 Config table saved: {fig_path}")


def main():
    rows = []

    for system, path in HPCC_FILES.items():
        if not os.path.isfile(path):
            print(f"❌ File not found: {path}")
            continue

        print(f"Processing file: {path}")
        with open(path) as f:
            lines = f.readlines()

        # Parse all metrics from the file
        metrics = parse_hpcc_output(lines)
        metrics["System"] = system
        rows.append(metrics)

    if not rows:
        raise SystemExit("❌ No valid HPCC logs found.")

    # Create dataframe with all metrics
    df = pd.DataFrame(rows)

    # Save full results to CSV
    csv_path = os.path.join(OUT_DIR, "hpcc_full_results.csv")
    df.to_csv(csv_path, index=False)
    print(f"📄 HPCC results saved to: {csv_path}")

    # Define simplified groups of related metrics for plotting
    metric_groups = {
        "HPL Performance": ["HPL_Tflops", "HPL_Best_Tflops"],
        "Matrix Operations": ["StarDGEMM_Gflops", "SingleDGEMM_Gflops"],
        "Memory Bandwidth": [
            "StarSTREAM_Triad",
            "SingleSTREAM_Triad",
        ],
        "RandomAccess": [
            "StarRandomAccess_GUPs",
            "SingleRandomAccess_GUPs",
        ],
        "FFT Performance": ["StarFFT_Gflops", "SingleFFT_Gflops"],
        "Communication": [
            "AvgPingPongLatency_usec",
            "AvgPingPongBandwidth_GBytes",
        ],
        "PTRANS": ["PTRANS_GBs"],
    }

    # Generate plots for each metric group
    generate_metric_plots(df, metric_groups, OUT_DIR)

    # Generate a combined performance plot
    generate_value_matrix_plot(df, IMPORTANT_METRICS, OUT_DIR)

    # Save configuration information
    save_configuration_info(df, CONFIG_METRICS, OUT_DIR)

    print(f"✅ Analysis complete. All results saved to {OUT_DIR}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
import os
import re

import matplotlib.pyplot as plt
import numpy as _np
import numpy as np
import pandas as pd

# Normalize axes into a 1D array called axes_flat


# Nord palette (elements only)
NORD_FG = "#2E3440"  # dark text/lines
NORD_GREEN = "#A3BE8C"  # winners
NORD_RED = "#BF616A"  # losers
NORD_GRAY = "#4C566A"  # neutrals

# Constants
OUT_DIR = "plots/hpcc"
os.makedirs(OUT_DIR, exist_ok=True)

HPCC_FILES = {
    "vms": "../results/vms/hpccoutf.txt",
    "containers": "../results/containers/hpccoutf.txt",
}

IMPORTANT_METRICS = [
    "HPL_Tflops",
    "StarDGEMM_Gflops",
    "StarSTREAM_Triad",
    "SingleSTREAM_Triad",
    "StarRandomAccess_GUPs",
    "SingleRandomAccess_GUPs",
    "StarFFT_Gflops",
    "SingleFFT_Gflops",
    "AvgPingPongLatency_usec",
    "AvgPingPongBandwidth_GBytes",
    "PTRANS_GBs",
]

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
    for line in lines:
        if "Current time" in line:
            m = re.search(r"Current time \(\d+\) is (.+)", line)
            if m:
                return m.group(1).strip()
    return "Unknown"


def parse_hpcc_output(lines):
    metrics = {}
    text = "\n".join(lines)
    # Summary section
    ss = text.find("Begin of Summary section.")
    se = text.find("End of Summary section.")
    if ss > 0 and se > ss:
        for l in text[ss:se].splitlines():
            if "=" in l:
                k, v = l.split("=", 1)
                k, v = k.strip(), v.strip()
                try:
                    metrics[k] = float(v)
                except:
                    metrics[k] = v
    metrics["Timestamp"] = extract_timestamp(lines)

    # HPL best
    m = re.search(r"End of HPL section", text)
    if m:
        snippet = text[: m.start()]
        best = 0
        for l in snippet.splitlines():
            if "WR11C2R4" in l:
                g = re.search(r"(\d+\.\d+)e\+(\d+)", l)
                if g:
                    val = float(g.group(1)) * 10 ** int(g.group(2))
                    best = max(best, val)
        if best:
            metrics["HPL_Best_Gflops"] = best
            metrics["HPL_Best_Tflops"] = best / 1000
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

        # Normalize axes into a 1D array called axes_flat
        import numpy as _np

        if not isinstance(axes, _np.ndarray):
            axes = _np.array([[axes]])
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
                winner_idx = _np.argmin(values)
                loser_idx = _np.argmax(values)
            else:
                winner_idx = _np.argmax(values)
                loser_idx = _np.argmin(values)

            # Create color list - winner green, loser red, others neutral (Nord palette)
            colors = [NORD_GRAY] * len(systems)  # Default neutral color
            colors[winner_idx] = NORD_GREEN  # Green for winner
            colors[loser_idx] = NORD_RED  # Red for loser

            # If only two systems, just use green and red
            if len(systems) == 2:
                if winner_idx == 0:
                    colors = [NORD_GREEN, NORD_RED]
                else:
                    colors = [NORD_RED, NORD_GREEN]

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


def generate_value_matrix_plot(df, metrics, out_dir):
    mets = [m for m in metrics if m in df.columns]
    if not mets:
        print("⚠️ No important metrics")
        return

    mat = df.set_index("System")[mets].T
    lower_better = {
        "AvgPingPongLatency_usec",
        "MinPingPongLatency_usec",
        "MaxPingPongLatency_usec",
        "PTRANS_time",
    }

    green, red, gray = NORD_GREEN, NORD_RED, NORD_GRAY
    cell_colors = []
    for m in mat.index:
        row = mat.loc[m]
        if m in lower_better:
            w, l = row.idxmin(), row.idxmax()
        else:
            w, l = row.idxmax(), row.idxmin()
        row_colors = [green if s == w else red if s == l else gray for s in mat.columns]
        cell_colors.append(row_colors)

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
        loc="center",
    )
    table.auto_set_font_size(False)
    table.set_fontsize(9)
    table.scale(1, 1.3)
    for (r, c), cell in table.get_celld().items():
        cell.get_text().set_color(NORD_FG)
        cell.set_edgecolor(NORD_GRAY)

    plt.tight_layout()
    path = os.path.join(out_dir, "performance_value_matrix.png")
    plt.savefig(path, dpi=100)
    plt.close(fig)
    print(f"📊 Saved {path}")


def save_configuration_info(df, configs, out_dir):
    avail = [m for m in configs if m in df.columns]
    if not avail:
        print("⚠️ No config data")
        return

    cfg = df[["System"] + avail]
    csv = os.path.join(out_dir, "hpcc_config.csv")
    cfg.to_csv(csv, index=False)
    print(f"📄 Saved {csv}")

    fig, ax = plt.subplots(figsize=(10, len(avail) * 0.25 + 1))
    ax.axis("off")
    tbl = ax.table(
        cellText=cfg.values, colLabels=cfg.columns, cellLoc="center", loc="center"
    )
    tbl.auto_set_font_size(False)
    tbl.set_fontsize(9)
    tbl.scale(1, 1.3)
    for key, cell in tbl.get_celld().items():
        cell.get_text().set_color(NORD_FG)
        cell.set_edgecolor(NORD_GRAY)

    path = os.path.join(out_dir, "system_config_table.png")
    plt.savefig(path, dpi=100)
    plt.close(fig)
    print(f"📊 Saved {path}")


def main():
    rows = []
    for sys, p in HPCC_FILES.items():
        if not os.path.isfile(p):
            print(f"❌ Missing: {p}")
            continue
        print(f"Processing {p}")
        lines = open(p).read().splitlines()
        m = parse_hpcc_output(lines)
        m["System"] = sys
        rows.append(m)

    if not rows:
        raise SystemExit("❌ No logs")

    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(OUT_DIR, "hpcc_full_results.csv"), index=False)
    print("📄 Full results saved")

    metric_groups = {
        "HPL Performance": ["HPL_Tflops", "HPL_Best_Tflops"],
        "Matrix Operations": ["StarDGEMM_Gflops", "SingleDGEMM_Gflops"],
        "Memory Bandwidth": ["StarSTREAM_Triad", "SingleSTREAM_Triad"],
        "RandomAccess": ["StarRandomAccess_GUPs", "SingleRandomAccess_GUPs"],
        "FFT Performance": ["StarFFT_Gflops", "SingleFFT_Gflops"],
        "Communication": ["AvgPingPongLatency_usec", "AvgPingPongBandwidth_GBytes"],
        "PTRANS": ["PTRANS_GBs"],
    }

    generate_metric_plots(df, metric_groups, OUT_DIR)
    generate_value_matrix_plot(df, IMPORTANT_METRICS, OUT_DIR)
    save_configuration_info(df, CONFIG_METRICS, OUT_DIR)

    print(f"✅ Done — all outputs in {OUT_DIR}")


if __name__ == "__main__":
    main()

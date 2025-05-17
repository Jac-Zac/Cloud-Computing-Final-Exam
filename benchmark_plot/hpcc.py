#!/usr/bin/env python3
import os
import re

import matplotlib.pyplot as plt
import numpy as _np
import pandas as pd

# Nord palette
NORD_FG = "#2E3440"
NORD_GREEN = "#A3BE8C"
NORD_RED = "#BF616A"
NORD_GRAY = "#808080"

# Output directory
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


def parse_hpcc_output(file_path, system_name):
    text = open(file_path).read()
    entries = []
    parts = re.split(r"Begin of Summary section\.", text)
    secs = parts[1:]

    for i, sec in enumerate(secs):
        part, _ = sec.split("End of Summary section.", 1)
        metrics = {}
        for l in part.splitlines():
            if "=" in l:
                k, v = l.split("=", 1)
                k, v = k.strip(), v.strip()
                try:
                    metrics[k] = float(v)
                except ValueError:
                    metrics[k] = v
        metrics["Timestamp"] = extract_timestamp(part.splitlines())
        metrics["System"] = system_name

        preceding_text = parts[i]
        hpl_start = preceding_text.find("Begin of HPL section.")
        hpl_end = preceding_text.find("End of HPL section.")
        if hpl_start != -1 and hpl_end != -1:
            hpl_section = preceding_text[hpl_start:hpl_end]
            for line in hpl_section.splitlines():
                line = line.strip()
                match = re.match(
                    r"^WR\S+\s+(\d+)\s+(\d+)\s+\d+\s+\d+\s+[\d.]+\s+([\d.e+-]+)$", line
                )
                if match:
                    n = int(match.group(1))
                    nb = int(match.group(2))
                    gflops = float(match.group(3))
                    hpl_metrics = metrics.copy()
                    hpl_metrics.update(
                        {
                            "HPL_N": n,
                            "HPL_NB": nb,
                            "HPL_Gflops": gflops,
                            "HPL_Tflops": gflops / 1000,
                        }
                    )
                    entries.append(hpl_metrics)
        entries.append(metrics)
    return entries


def generate_metric_plots(df, metric_groups, out_dir, dpi=200):
    lower_is_better = ["AvgPingPongLatency_usec", "PTRANS_time"]
    for group, metrics in metric_groups.items():
        available = [m for m in metrics if m in df]
        if not available:
            print(f"⚠️ No data for {group}")
            continue
        rows = (len(available) + 1) // 2
        cols = min(2, len(available))
        fig, axes = plt.subplots(rows, cols, figsize=(12, 4 * rows), squeeze=False)
        axes_flat = axes.flatten()
        systems = df["System"].unique()
        for i, metric in enumerate(available):
            ax = axes_flat[i]
            # Ensure grid is drawn behind bars
            ax.set_axisbelow(True)
            ax.grid(axis="y", linestyle="--", alpha=0.5, zorder=0)
            # Gather values
            vals = [df[df.System == s][metric].iloc[-1] for s in systems]
            if metric in lower_is_better:
                wi, li = _np.argmin(vals), _np.argmax(vals)
            else:
                wi, li = _np.argmax(vals), _np.argmin(vals)
            colors = [NORD_GRAY] * len(systems)
            colors[wi], colors[li] = NORD_GREEN, NORD_RED
            # Plot bars above grid
            bars = ax.bar(systems, vals, color=colors, zorder=3)
            for bar, v in zip(bars, vals):
                ax.text(
                    bar.get_x() + bar.get_width() / 2,
                    v * 1.01,
                    f"{v:.3g}",
                    ha="center",
                    zorder=4,
                )
            ax.set_title(metric.replace("_", " "), color=NORD_FG)
            ax.set_ylabel(metric.split("_")[-1], color=NORD_FG)
            ax.tick_params(axis="x", rotation=45, colors=NORD_FG)
            ax.tick_params(axis="y", colors=NORD_FG)
            better = (
                "Lower is better" if metric in lower_is_better else "Higher is better"
            )
            ax.annotate(
                better,
                xy=(0.5, 0.97),
                xycoords="axes fraction",
                ha="center",
                fontsize=8,
                style="italic",
                color=NORD_FG,
                zorder=5,
            )
            for spine in ax.spines.values():
                spine.set_color(NORD_GRAY)
        for j in range(len(available), len(axes_flat)):
            axes_flat[j].axis("off")
        plt.tight_layout()
        path = os.path.join(out_dir, f"{group.lower().replace(' ','_')}.png")
        fig.savefig(path, dpi=dpi, bbox_inches="tight")
        plt.close(fig)
        print(f"📊 Saved: {path}")


def generate_hpl_scaling_plot(df, out_dir, dpi=200):
    """
    Plot HPL_Gflops vs HPL_N for each System using Nord colors,
    and save the processed CSV data used for plotting.
    """
    hpl_df = df.dropna(subset=["HPL_Gflops"])
    if hpl_df.empty:
        print("⚠️ No HPL test data")
        return

    hpl_max = hpl_df.groupby(["System", "HPL_N"])["HPL_Gflops"].max().reset_index()

    # Save the processed data to CSV
    csv_path = os.path.join(out_dir, "hpl_scaling_data.csv")
    hpl_max.to_csv(csv_path, index=False)
    print(f"💾 Saved CSV data for plot: {csv_path}")

    plt.figure(figsize=(8, 5))
    for sys, grp in hpl_max.groupby("System"):
        grp_sorted = grp.sort_values("HPL_N")
        color = NORD_RED if sys == "vms" else NORD_GREEN
        plt.plot(
            grp_sorted["HPL_N"],
            grp_sorted["HPL_Gflops"] / 1000,
            marker="o",
            color=color,
            label=sys,
            linewidth=2,
            markersize=8,
        )

    plt.gca().set_facecolor("white")
    plt.grid(True, linestyle="--", alpha=0.7, color=NORD_GRAY)
    plt.title("HPL Scaling: Performance vs Problem Size", color=NORD_FG, pad=20)
    plt.xlabel("Problem Size (HPL_N)", color=NORD_FG)
    plt.ylabel("Performance (Tflops)", color=NORD_FG)
    plt.legend(title="System", title_fontsize=10)

    plt.tick_params(axis="both", colors=NORD_GRAY)
    for spine in plt.gca().spines.values():
        spine.set_color(NORD_GRAY)

    plt.tight_layout()
    path = os.path.join(out_dir, "hpl_scaling.png")
    plt.savefig(path, dpi=dpi, bbox_inches="tight")
    plt.close()
    print(f"📈 Saved HPL scaling plot: {path}")


def generate_value_matrix_plot(df, metrics, out_dir, dpi=200):
    # Filter to only include metrics from largest problem size runs
    mets = [m for m in metrics if m in df]
    if not mets:
        print("⚠️ No important metrics")
        return

    mat = df.set_index("System")[mets].T

    lower_better = {"AvgPingPongLatency_usec"}
    colors = []
    for m in mat.index:
        row = mat.loc[m]
        w, l = (
            (row.idxmin(), row.idxmax())
            if m in lower_better
            else (row.idxmax(), row.idxmin())
        )
        # Direct color assignment based on system name
        colors.append(
            [
                (NORD_GREEN if c == "containers" else NORD_RED) if c == w else NORD_GRAY
                for c in mat.columns
            ]
        )

    fig, ax = plt.subplots(
        figsize=(1.5 * len(mat.columns) + 2, 0.5 * len(mat.index) + 2)
    )
    ax.axis("off")

    # Create table with styled text
    cell_text = []
    for idx, row in mat.iterrows():
        formatted_row = []
        for val in row:
            if "Tflops" in idx:
                formatted_row.append(f"{val:.3f}")
            elif "Latency" in idx:
                formatted_row.append(f"{val:.1f}")
            else:
                formatted_row.append(f"{val:.2f}")
        cell_text.append(formatted_row)

    table = ax.table(
        cellText=cell_text,
        rowLabels=mat.index.str.replace("_", " "),
        colLabels=mat.columns,
        cellColours=colors,
        loc="center",
        cellLoc="center",
    )

    # Style table
    table.auto_set_font_size(False)
    table.set_fontsize(10)
    table.scale(1, 1.5)

    # Set colors and alignment
    for key, cell in table.get_celld().items():
        cell.get_text().set_color(NORD_FG)
        cell.set_edgecolor(NORD_GRAY)
        cell.set_linewidth(0.5)

    plt.tight_layout()
    path = os.path.join(out_dir, "performance_value_matrix.png")
    fig.savefig(path, dpi=dpi, bbox_inches="tight")
    plt.close(fig)
    print(f"📊 Saved: {path}")


def get_matrix_dataframe(df):
    """Filter dataframe to include only runs with largest HPL_N per system"""
    hpl_test_entries = df[df["HPL_N"].notna()]
    if hpl_test_entries.empty:
        return df

    # Find max HPL_N per run
    hpl_max_per_run = (
        hpl_test_entries.groupby(["System", "Timestamp"])["HPL_N"].max().reset_index()
    )

    # Find max HPL_N per system
    max_hpl_per_system = hpl_max_per_run.groupby("System")["HPL_N"].max().reset_index()

    # Get corresponding timestamps
    max_hpl_runs = max_hpl_per_system.merge(
        hpl_max_per_run, on=["System", "HPL_N"], how="left"
    )

    # Get summary entries for these runs
    matrix_df = df[df["HPL_N"].isna()].merge(
        max_hpl_runs[["System", "Timestamp"]], on=["System", "Timestamp"], how="inner"
    )

    return matrix_df


def save_configuration_info(df, configs, out_dir):
    avail = [m for m in configs if m in df]
    if not avail:
        print("⚠️ No config data")
        return
    csv = os.path.join(out_dir, "hpcc_config.csv")
    df[["System"] + avail].to_csv(csv, index=False)
    print(f"📄 Saved: {csv}")


def main():
    rows = []
    for sys, path in HPCC_FILES.items():
        if not os.path.isfile(path):
            print(f"❌ Missing: {path}")
            continue
        print(f"Processing {path}")
        rows.extend(parse_hpcc_output(path, sys))
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
        "Communication": ["AvgPingPongLatency_usec", "AvgPingPongBandwidth_GBytes"],
        "PTRANS": ["PTRANS_GBs"],
    }

    generate_metric_plots(df, metric_groups, OUT_DIR)
    generate_hpl_scaling_plot(df, OUT_DIR)
    generate_value_matrix_plot(df, IMPORTANT_METRICS, OUT_DIR)
    save_configuration_info(df, CONFIG_METRICS, OUT_DIR)

    print(f"✅ Done — all outputs in {OUT_DIR}")


if __name__ == "__main__":
    main()

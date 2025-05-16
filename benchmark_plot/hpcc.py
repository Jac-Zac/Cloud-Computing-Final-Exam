#!/usr/bin/env python3
import os
import re

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

# Nord color palette
NORD_FG = "#2E3440"
NORD_GREEN = "#A3BE8C"
NORD_RED = "#BF616A"
NORD_GRAY = "#4C566A"

# Output configuration
OUT_DIR = "plots/hpcc"
os.makedirs(OUT_DIR, exist_ok=True)

# Input files per system
HPCC_FILES = {
    "vms": "../results/vms/hpccoutf.txt",
    "containers": "../results/containers/hpccoutf.txt",
}

# Metrics configuration
IMPORTANT_METRICS = [
    "HPL_Tflops",
    "StarDGEMM_Gflops",
    "StarSTREAM_Triad",
    "AvgPingPongLatency_usec",
    "PTRANS_GBs",
    "SingleRandomAccess_GUPs",
]

CONFIG_METRICS = ["HPL_N", "HPL_NB", "CommWorldProcs", "MPI_Wtick"]


def extract_timestamp(lines):
    for line in lines:
        if "Current time" in line:
            match = re.search(r"Current time \(\d+\) is (.+)", line)
            if match:
                return match.group(1).strip()
    return "Unknown"


def parse_hpcc_output(file_path, system_name):
    """Parse HPCC output with detailed HPL test extraction"""
    with open(file_path) as f:
        text = f.read()

    entries = []
    summary_sections = re.split(r"Begin of Summary section\.", text)[1:]

    for sec in summary_sections:
        part, _ = sec.split("End of Summary section.", 1)
        metrics = {}

        # Parse key-value pairs from summary
        for line in part.splitlines():
            if "=" in line:
                key, val = line.split("=", 1)
                key = key.strip()
                try:
                    metrics[key] = float(val.strip())
                except (ValueError, TypeError):
                    metrics[key] = val.strip()

        metrics["Timestamp"] = extract_timestamp(part.splitlines())
        metrics["System"] = system_name

        # Extract detailed HPL tests from HPL section
        hpl_section = re.search(
            r"Begin of HPL section(.*?)End of HPL section", text, re.DOTALL
        )
        if hpl_section:
            hpl_content = hpl_section.group(1)
            hpl_tests = re.findall(
                r"WR11C2R4\s+(\d+)\s+(\d+)\s+\d+\s+\d+\s+(\d+\.\d+)\s+([\d.e+]+)",
                hpl_content,
            )
            for n, nb, time, gflops in hpl_tests:
                test_entry = metrics.copy()
                test_entry.update(
                    {
                        "HPL_N": int(n),
                        "HPL_NB": int(nb),
                        "HPL_Time": float(time),
                        "HPL_Gflops": float(gflops),
                        "HPL_Tflops": float(gflops) / 1000,
                    }
                )
                entries.append(test_entry)
        else:
            entries.append(metrics)

    return entries


def generate_metric_plots(df, metric_groups, out_dir, dpi=200):
    """Generate bar plots for metric groups"""
    lower_is_better = ["AvgPingPongLatency_usec"]
    for group_name, metrics in metric_groups.items():
        valid_metrics = [m for m in metrics if m in df]
        if not valid_metrics:
            print(f"⚠️ No data for {group_name}")
            continue

        n_metrics = len(valid_metrics)
        rows = (n_metrics + 1) // 2
        cols = min(2, n_metrics)

        fig, axes = plt.subplots(rows, cols, figsize=(12, 4 * rows))
        axes = axes.flatten() if rows > 1 else [axes]

        systems = df["System"].unique()
        colors = [NORD_GREEN, NORD_RED][: len(systems)]

        for idx, metric in enumerate(valid_metrics):
            ax = axes[idx]
            sys_values = [df[df.System == sys][metric].iloc[-1] for sys in systems]

            if metric in lower_is_better:
                best_idx = np.argmin(sys_values)
            else:
                best_idx = np.argmax(sys_values)

            bar_colors = [NORD_GRAY] * len(systems)
            bar_colors[best_idx] = NORD_GREEN
            if len(systems) == 2:
                bar_colors = (
                    [NORD_GREEN, NORD_RED] if best_idx == 0 else [NORD_RED, NORD_GREEN]
                )

            bars = ax.bar(systems, sys_values, color=bar_colors)
            ax.set_title(metric.replace("_", " "), pad=12)
            ax.set_ylabel(metric.split("_")[-1])
            ax.tick_params(axis="x", rotation=45)

            # Add value labels
            for bar in bars:
                height = bar.get_height()
                ax.text(
                    bar.get_x() + bar.get_width() / 2,
                    height * 1.02,
                    f"{height:.2f}",
                    ha="center",
                    fontsize=9,
                )

            # Add performance annotation
            perf_note = "Lower better" if metric in lower_is_better else "Higher better"
            ax.annotate(
                perf_note,
                xy=(0.5, 0.95),
                xycoords="axes fraction",
                ha="center",
                fontsize=9,
                style="italic",
            )

        # Hide unused axes
        for j in range(len(valid_metrics), len(axes)):
            axes[j].axis("off")

        plt.tight_layout()
        filename = f"{group_name.lower().replace(' ', '_')}.png"
        fig.savefig(os.path.join(out_dir, filename), dpi=dpi, bbox_inches="tight")
        plt.close()
        print(f"📊 Saved {filename}")


def generate_hpl_comparison(df, out_dir, dpi=200):
    """Generate HPL problem size comparison plot"""
    if "HPL_N" not in df or "HPL_Tflops" not in df:
        print("⚠️ Missing HPL data")
        return

    # Aggregate data to get best Tflops per problem size
    agg_df = df.groupby(["System", "HPL_N"])["HPL_Tflops"].max().reset_index()
    systems = agg_df["System"].unique()
    problem_sizes = sorted(agg_df["HPL_N"].unique())

    # Plot configuration
    bar_width = 0.35
    index = np.arange(len(problem_sizes))
    colors = [NORD_GREEN, NORD_RED]

    plt.figure(figsize=(12, 7))

    for i, system in enumerate(systems):
        sys_data = agg_df[agg_df["System"] == system]
        positions = index + i * bar_width
        plt.bar(
            positions,
            sys_data["HPL_Tflops"],
            bar_width,
            label=system,
            color=colors[i],
            edgecolor=NORD_FG,
            linewidth=0.5,
        )

        # Add value labels
        for x, y in zip(positions, sys_data["HPL_Tflops"]):
            plt.text(x, y + 0.1, f"{y:.2f}", ha="center", va="bottom", fontsize=9)

    plt.xlabel("Problem Size (N)", fontsize=12)
    plt.ylabel("Performance (Tflops)", fontsize=12)
    plt.title("HPL Performance Comparison by Problem Size", pad=15)
    plt.xticks(index + bar_width / 2, problem_sizes)
    plt.legend()
    plt.grid(True, linestyle="--", alpha=0.3)

    plt.tight_layout()
    filename = os.path.join(out_dir, "hpl_problem_size_comparison.png")
    plt.savefig(filename, dpi=dpi, bbox_inches="tight")
    plt.close()
    print(f"📈 Saved HPL comparison plot: {filename}")


def generate_value_matrix(df, metrics, out_dir, dpi=200):
    """Generate performance value matrix"""
    valid_metrics = [m for m in metrics if m in df]
    if not valid_metrics:
        print("⚠️ No valid metrics for matrix")
        return

    matrix = df.set_index("System")[valid_metrics].T
    lower_better = {"AvgPingPongLatency_usec"}

    fig, ax = plt.subplots(
        figsize=(1.5 * len(matrix.columns) + 2, 0.5 * len(matrix.index) + 2)
    )
    ax.axis("off")

    cell_colors = []
    for metric in matrix.index:
        row = matrix.loc[metric]
        if metric in lower_better:
            best = row.idxmin()
            worst = row.idxmax()
        else:
            best = row.idxmax()
            worst = row.idxmin()

        colors = []
        for sys in matrix.columns:
            if sys == best:
                colors.append(NORD_GREEN)
            elif sys == worst:
                colors.append(NORD_RED)
            else:
                colors.append(NORD_GRAY)
        cell_colors.append(colors)

    table = ax.table(
        cellText=matrix.values.round(2),
        rowLabels=[m.replace("_", " ") for m in matrix.index],
        colLabels=matrix.columns,
        cellColours=cell_colors,
        loc="center",
        cellLoc="center",
    )

    table.auto_set_font_size(False)
    table.set_fontsize(10)
    for key, cell in table.get_celld().items():
        cell.get_text().set_color(NORD_FG)
        cell.set_edgecolor(NORD_GRAY)

    plt.tight_layout()
    filename = os.path.join(out_dir, "performance_matrix.png")
    plt.savefig(filename, dpi=dpi, bbox_inches="tight")
    plt.close()
    print(f"📊 Saved performance matrix: {filename}")


def save_config_info(df, metrics, out_dir):
    """Save configuration information"""
    valid_metrics = [m for m in metrics if m in df]
    if not valid_metrics:
        print("⚠️ No configuration metrics")
        return

    # Save CSV
    csv_path = os.path.join(out_dir, "config_summary.csv")
    df[["System"] + valid_metrics].to_csv(csv_path, index=False)
    print(f"📄 Saved config CSV: {csv_path}")

    # Save table image
    fig, ax = plt.subplots(figsize=(10, 0.5 * len(valid_metrics) + 1))
    ax.axis("off")

    table = ax.table(
        cellText=df[["System"] + valid_metrics].values,
        colLabels=["System"] + valid_metrics,
        loc="center",
        cellLoc="center",
    )

    table.auto_set_font_size(False)
    table.set_fontsize(10)
    for key, cell in table.get_celld().items():
        cell.get_text().set_color(NORD_FG)
        cell.set_edgecolor(NORD_GRAY)

    plt.tight_layout()
    img_path = os.path.join(out_dir, "config_table.png")
    plt.savefig(img_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"📊 Saved config table: {img_path}")


def main():
    all_data = []
    for system, path in HPCC_FILES.items():
        if not os.path.exists(path):
            print(f"❌ Missing file: {path}")
            continue

        print(f"Processing {system}...")
        entries = parse_hpcc_output(path, system)
        all_data.extend(entries)

    if not all_data:
        raise RuntimeError("No data processed")

    df = pd.DataFrame(all_data)
    csv_path = os.path.join(OUT_DIR, "full_results.csv")
    df.to_csv(csv_path, index=False)
    print(f"💾 Saved full results to {csv_path}")

    # Define metric groups for visualization
    metric_groups = {
        "Compute Performance": ["StarDGEMM_Gflops", "SingleDGEMM_Gflops"],
        "Memory Performance": ["StarSTREAM_Triad", "SingleSTREAM_Triad"],
        "Network Performance": [
            "AvgPingPongLatency_usec",
            "AvgPingPongBandwidth_GBytes",
        ],
        "Random Access": ["SingleRandomAccess_GUPs", "StarRandomAccess_GUPs"],
    }

    generate_metric_plots(df, metric_groups, OUT_DIR)
    generate_hpl_comparison(df, OUT_DIR)
    generate_value_matrix(df, IMPORTANT_METRICS, OUT_DIR)
    save_config_info(df, CONFIG_METRICS, OUT_DIR)

    print(f"✅ All outputs saved to {OUT_DIR}")


if __name__ == "__main__":
    main()

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
NORD_GRAY = "#4C566A"

# Output directory
OUT_DIR = "plots/hpcc"
os.makedirs(OUT_DIR, exist_ok=True)

# Input files per system
HPCC_FILES = {
    "vms": "../results/vms/hpccoutf.txt",
    "containers": "../results/containers/hpccoutf.txt",
}

# Metrics of interest
IMPORTANT_METRICS = [
    "HPL_Tflops",
    "HPL_Best_Gflops",
    "StarDGEMM_Gflops",
    "StarSTREAM_Triad",
    "AvgPingPongLatency_usec",
    # ... other metrics
]
CONFIG_METRICS = [
    "HPL_N",
    "HPL_NB",
    "CommWorldProcs",
    # ... other configs
]


def extract_timestamp(lines):
    for line in lines:
        if "Current time" in line:
            m = re.search(r"Current time \(\d+\) is (.+)", line)
            if m:
                return m.group(1).strip()
    return "Unknown"


def parse_hpcc_output(file_path, system_name):
    """
    Parse all summary sections in an HPCC output file, return one dict per run.
    """
    text = open(file_path).read()
    entries = []
    secs = re.split(r"Begin of Summary section\.", text)[1:]
    for sec in secs:
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
        # best HPL
        best = 0
        for l in text[: text.find("End of HPL section")].splitlines():
            if "WR11C2R4" in l:
                g = re.search(r"(\d+\.\d+)e\+(\d+)", l)
                if g:
                    val = float(g.group(1)) * 10 ** int(g.group(2))
                    best = max(best, val)
        if best:
            metrics["HPL_Best_Gflops"] = best
            metrics["HPL_Best_Tflops"] = best / 1e3
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
            vals = [df[df.System == s][metric].iloc[-1] for s in systems]
            if metric in lower_is_better:
                wi, li = _np.argmin(vals), _np.argmax(vals)
            else:
                wi, li = _np.argmax(vals), _np.argmin(vals)
            colors = [NORD_GRAY] * len(systems)
            colors[wi], colors[li] = NORD_GREEN, NORD_RED
            if len(systems) == 2:
                colors = [NORD_GREEN, NORD_RED] if wi == 0 else [NORD_RED, NORD_GREEN]
            bars = ax.bar(systems, vals, color=colors)
            for bar, v in zip(bars, vals):
                ax.text(
                    bar.get_x() + bar.get_width() / 2, v * 1.01, f"{v:.3g}", ha="center"
                )
            ax.set_title(metric.replace("_", " "))
            ax.set_ylabel(metric.split("_")[-1])
            ax.tick_params(axis="x", rotation=45)
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
            )
        for j in range(len(available), len(axes_flat)):
            axes_flat[j].axis("off")
        plt.tight_layout()
        path = os.path.join(out_dir, f"{group.lower().replace(' ','_')}.png")
        fig.savefig(path, dpi=dpi, bbox_inches="tight")
        plt.close(fig)
        print(f"📊 Saved: {path}")


def generate_hpl_scaling_plot(df, out_dir, dpi=200):
    """
    Plot HPL_Best_Tflops vs HPL_N for each System.
    """
    if "HPL_N" not in df or "HPL_Best_Tflops" not in df:
        print("⚠️ Missing HPL_N or HPL_Best_Tflops")
        return
    plt.figure(figsize=(8, 5))
    for sys, grp in df.groupby("System"):
        # sort by HPL_N
        grp_sorted = grp.sort_values("HPL_N")
        plt.plot(
            grp_sorted["HPL_N"], grp_sorted["HPL_Best_Tflops"], marker="o", label=sys
        )
    plt.xlabel("Problem Size (HPL_N)")
    plt.ylabel("Performance (Tflops)")
    plt.title("HPL Scaling: Performance vs Problem Size")
    plt.legend()
    plt.grid(True, linestyle="--", alpha=0.5)
    path = os.path.join(out_dir, "hpl_scaling.png")
    plt.savefig(path, dpi=dpi, bbox_inches="tight")
    plt.close()
    print(f"📈 Saved HPL scaling plot: {path}")


def generate_value_matrix_plot(df, metrics, out_dir, dpi=200):
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
        colors.append(
            [
                NORD_GREEN if c == w else NORD_RED if c == l else NORD_GRAY
                for c in mat.columns
            ]
        )
    fig, ax = plt.subplots(
        figsize=(1.5 * len(mat.columns) + 2, 0.5 * len(mat.index) + 2)
    )
    ax.axis("off")
    table = ax.table(
        cellText=mat.values,
        rowLabels=mat.index.str.replace("_", " "),
        colLabels=mat.columns,
        cellColours=colors,
        loc="center",
    )
    table.auto_set_font_size(False)
    table.set_fontsize(9)
    for key, cell in table.get_celld().items():
        cell.get_text().set_color(NORD_FG)
        cell.set_edgecolor(NORD_GRAY)
    plt.tight_layout()
    path = os.path.join(out_dir, "performance_value_matrix.png")
    fig.savefig(path, dpi=dpi)
    plt.close(fig)
    print(f"📊 Saved: {path}")


def save_configuration_info(df, configs, out_dir, dpi=200):
    avail = [m for m in configs if m in df]
    if not avail:
        print("⚠️ No config data")
        return
    csv = os.path.join(out_dir, "hpcc_config.csv")
    df[["System"] + avail].to_csv(csv, index=False)
    print(f"📄 Saved: {csv}")
    fig, ax = plt.subplots(figsize=(10, len(avail) * 0.3 + 1))
    ax.axis("off")
    tbl = ax.table(
        cellText=df[["System"] + avail].values,
        colLabels=["System"] + avail,
        loc="center",
    )
    tbl.auto_set_font_size(False)
    tbl.set_fontsize(9)
    for key, cell in tbl.get_celld().items():
        cell.get_text().set_color(NORD_FG)
        cell.set_edgecolor(NORD_GRAY)
    plt.tight_layout()
    path = os.path.join(out_dir, "system_config_table.png")
    fig.savefig(path, dpi=dpi)
    plt.close(fig)
    print(f"📊 Saved: {path}")


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

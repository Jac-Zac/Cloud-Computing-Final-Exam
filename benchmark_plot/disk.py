#!/usr/bin/env python3
import os
import re
import string

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from mpl_toolkits.mplot3d import Axes3D  # noqa: F401 for 3D projection

# Nord palette accents for bar charts
NORD_LOCAL = "#88C0D0"  # Nord 9
NORD_SHARED = "#81A1C1"  # Nord 10
NORD_CONTAINER = "#5E81AC"  # Nord 11
NORD_VM = "#B48EAD"  # Nord 15

plt.style.use("ggplot")  # Base style; custom colors applied manually where needed


def sanitize_filename(s):
    valid = f"{string.ascii_letters}{string.digits}"
    cleaned = "".join(c if c in valid else "_" for c in s)
    cleaned = re.sub(r"_+", "_", cleaned)
    return cleaned.strip("_")


def discover_disk_logs(root):
    logs = {}
    for system in ("containers", "vms"):
        d = os.path.join(root, system, "disk")
        if not os.path.isdir(d):
            print(f"[WARN] Directory not found: {d}")
            continue
        for fname in os.listdir(d):
            if not fname.endswith(".log"):
                continue
            base = os.path.splitext(fname)[0]
            role = base.split("_")[0]
            env = "container" if system == "containers" else "vm"
            logs[f"{role} ({env})"] = os.path.join(d, fname)
    return logs


def parse_iozone(lines, metrics):
    sections = {"local": [], "shared": []}
    current = None
    for ln in lines:
        line = ln.strip()
        if re.search(r"starting benchmark for:\s*local", line, re.IGNORECASE):
            current = "local"
            continue
        if re.search(r"--- iozone shared filesystem test ---", line, re.IGNORECASE):
            current = "shared"
            continue
        if current and re.match(r"^\d", line):
            parts = line.split()
            if len(parts) >= 15:
                try:
                    kb = int(parts[0])
                    if kb <= 64:
                        continue  # skip small sizes
                    reclen = int(parts[1])
                    values = list(map(float, parts[2 : 2 + len(metrics)]))
                    entry = {"section": current, "kB": kb, "reclen": reclen}
                    entry.update({metrics[i]: values[i] for i in range(len(metrics))})
                    sections[current].append(entry)
                except ValueError:
                    pass
    return pd.DataFrame(sections["local"]), pd.DataFrame(sections["shared"])


if __name__ == "__main__":
    root = os.path.dirname(__file__)
    results_root = os.path.join(root, "../results")
    out_dir = os.path.join(root, "plots/disk")
    os.makedirs(out_dir, exist_ok=True)

    metrics = [
        "Write (kB/s)",
        "Rewrite (kB/s)",
        "Read (kB/s)",
        "Reread (kB/s)",
        "Random Read (kB/s)",
        "Random Write (kB/s)",
        "Bkwd Read (kB/s)",
        "Record Rewrite (kB/s)",
        "Stride Read (kB/s)",
        "Fwrite (kB/s)",
        "Frewrite (kB/s)",
        "Fread (kB/s)",
        "Freread (kB/s)",
    ]

    records = []
    logs = discover_disk_logs(results_root)
    if not logs:
        raise SystemExit("❌ No disk logs found")

    for label, path in logs.items():
        role, env = label.split()
        env = env.strip("()").lower()
        lines = open(path).readlines()
        df_local, df_shared = parse_iozone(lines, metrics)
        for df in (df_local, df_shared):
            if df.empty:
                continue
            df["role"] = role
            df["environment"] = env
            records.append(df)

    full_df = pd.concat(records, ignore_index=True)
    long_df = full_df.melt(
        id_vars=["environment", "role", "section", "kB", "reclen"],
        value_vars=metrics,
        var_name="metric",
        value_name="value",
    )

    # Save summary CSV for later use
    csv_path = os.path.join(out_dir, "disk_summary.csv")
    long_df.to_csv(csv_path, index=False)
    print(f"📄 Saved summary CSV: {csv_path}")

    # Generate 4-way 3D surface plots
    for (role, metric), grp in long_df.groupby(["role", "metric"]):
        envs = set(grp["environment"])
        secs = set(grp["section"])
        if not envs.issuperset({"vm", "container"}) or not secs.issuperset(
            {"local", "shared"}
        ):
            continue

        # Prepare grid indices
        kb_vals = sorted(grp["kB"].unique())
        rl_vals = sorted(grp["reclen"].unique())
        x = np.arange(len(kb_vals))
        y = np.arange(len(rl_vals))
        kb_ix = {k: i for i, k in enumerate(kb_vals)}
        rl_ix = {r: i for i, r in enumerate(rl_vals)}

        # Populate Z matrices
        Z = {
            (e, s): np.full((len(rl_vals), len(kb_vals)), np.nan)
            for e in ("vm", "container")
            for s in ("local", "shared")
        }
        for _, r in grp.iterrows():
            Z[(r["environment"], r["section"])]
            Z[(r["environment"], r["section"])][rl_ix[r["reclen"]], kb_ix[r["kB"]]] = r[
                "value"
            ]

        zmin = min(np.nanmin(m) for m in Z.values())
        zmax = max(np.nanmax(m) for m in Z.values())

        # Create 3D figure
        fig = plt.figure(figsize=(20, 18))
        fig.suptitle(
            f"Role: {role}   Metric: {metric}", fontsize=18, y=0.95, weight="semibold"
        )
        elev, azim = 25, -60
        pos_map = {
            ("vm", "local"): 1,
            ("vm", "shared"): 2,
            ("container", "local"): 3,
            ("container", "shared"): 4,
        }

        for (env, sec), idx in pos_map.items():
            ax = fig.add_subplot(2, 2, idx, projection="3d")
            surf = ax.plot_surface(
                *np.meshgrid(x, y),
                Z[(env, sec)],
                cmap="viridis",
                edgecolor="none",
                alpha=0.8,
            )
            ax.set_title(f"{env.upper()} - {sec.capitalize()}", fontsize=14, pad=12)
            # Axis labels and ticks
            step_x = max(1, len(kb_vals) // 6)
            ax.set_xticks(x[::step_x])
            ax.set_xticklabels(kb_vals[::step_x], rotation=35, ha="right", fontsize=10)
            step_y = max(1, len(rl_vals) // 6)
            ax.set_yticks(y[::step_y])
            ax.set_yticklabels(rl_vals[::step_y], ha="center", va="center", fontsize=10)
            ax.set_xlabel("File Size (kB)", labelpad=10, fontsize=12)
            ax.set_ylabel("Record Size (bytes)", labelpad=10, fontsize=12)
            ax.set_zlabel(metric, labelpad=10, fontsize=12)
            ax.set_zlim(zmin, zmax)
            ax.view_init(elev=elev, azim=azim)
            ax.grid(True, linestyle=":", alpha=0.5)

        # Adjust layout and add colorbar
        plt.subplots_adjust(
            left=0.08, right=0.88, top=0.88, bottom=0.08, wspace=0.25, hspace=0.25
        )
        cbar = fig.colorbar(
            surf, ax=fig.get_axes(), shrink=0.6, aspect=25, pad=0.05, location="right"
        )
        cbar.ax.tick_params(labelsize=10)
        cbar.ax.set_ylabel(metric, fontsize=12, rotation=-90, va="bottom")

        # Save 3D figure
        fname_3d = sanitize_filename(f"{role}_{metric}_4way") + ".png"
        save_path_3d = os.path.join(out_dir, fname_3d)
        fig.savefig(save_path_3d, dpi=300, bbox_inches="tight", pad_inches=0.2)
        plt.close(fig)
        print(f"📈 Saved: {save_path_3d}")

    # ------------------------------------------------------------
    # Additional 2D bar chart: average throughput per metric (Local vs Shared)
    # ------------------------------------------------------------
    # Compute overall average for each metric and section
    summary = long_df.groupby(["metric", "section"])["value"].mean().unstack()
    operations = summary.index.tolist()
    local_vals = summary["local"].tolist()
    shared_vals = summary["shared"].tolist()

    # Plot bar chart with Nord theme colors
    plt.figure(figsize=(14, 7))
    bar_width = 0.35
    indices = np.arange(len(operations))

    plt.bar(
        indices, local_vals, width=bar_width, label="Local (IOzone)", color=NORD_LOCAL
    )
    plt.bar(
        indices + bar_width,
        shared_vals,
        width=bar_width,
        label="Shared (IOzone)",
        color=NORD_SHARED,
    )

    plt.xticks(indices + bar_width / 2, operations, rotation=45, ha="right")
    plt.ylabel("Average Throughput (kB/s)", fontsize=12)
    plt.title("Average IOzone Throughput by Metric: Local vs Shared", fontsize=16)
    plt.legend()
    plt.grid(axis="y", linestyle="--", alpha=0.5)
    plt.tight_layout()

    # Save bar chart
    fname_bar = "iozone_local_vs_shared_bar_nord.png"
    save_path_bar = os.path.join(out_dir, fname_bar)
    plt.savefig(save_path_bar, dpi=300)
    plt.close()
    print(f"📊 Saved bar comparison: {save_path_bar}")

    # ------------------------------------------------------------
    # NEW PLOT: Compare VM vs Container for both Local and Shared filesystems
    # ------------------------------------------------------------
    # Group by environment, section, and metric to get averages
    env_comparison = (
        long_df.groupby(["environment", "section", "metric"])["value"]
        .mean()
        .reset_index()
    )

    # Pivot to get the data in the right format for plotting
    pivot_df = env_comparison.pivot_table(
        index="metric", columns=["environment", "section"], values="value"
    ).reset_index()

    # Get operation names (metrics)
    operations = pivot_df["metric"].tolist()

    # Extract values for our four categories
    vm_local = pivot_df[("vm", "local")].tolist()
    vm_shared = pivot_df[("vm", "shared")].tolist()
    container_local = pivot_df[("container", "local")].tolist()
    container_shared = pivot_df[("container", "shared")].tolist()

    # Create plot with Nord theme colors
    plt.figure(figsize=(16, 8))
    bar_width = 0.2
    indices = np.arange(len(operations))

    # Plot the four categories
    plt.bar(
        indices - bar_width * 1.5,
        vm_local,
        width=bar_width,
        label="VM - Local",
        color=NORD_VM,
        alpha=0.9,
    )
    plt.bar(
        indices - bar_width / 2,
        vm_shared,
        width=bar_width,
        label="VM - Shared",
        color=NORD_VM,
        alpha=0.6,
    )
    plt.bar(
        indices + bar_width / 2,
        container_local,
        width=bar_width,
        label="Container - Local",
        color=NORD_CONTAINER,
        alpha=0.9,
    )
    plt.bar(
        indices + bar_width * 1.5,
        container_shared,
        width=bar_width,
        label="Container - Shared",
        color=NORD_CONTAINER,
        alpha=0.6,
    )

    # Add labels, title, and legend
    plt.xlabel("Operation", fontsize=12)
    plt.ylabel("Average Throughput (kB/s)", fontsize=12)
    plt.title(
        "IOzone Performance: VM vs Container, Local vs Shared Filesystems", fontsize=16
    )
    plt.xticks(indices, operations, rotation=45, ha="right")
    plt.legend(loc="upper left", bbox_to_anchor=(1, 1))
    plt.grid(axis="y", linestyle="--", alpha=0.5)

    # Adjust layout
    plt.tight_layout()

    # Save comparison plot
    fname_comp = "iozone_vm_vs_container_local_vs_shared_nord.png"
    save_path_comp = os.path.join(out_dir, fname_comp)
    plt.savefig(save_path_comp, dpi=300, bbox_inches="tight")
    plt.close()
    print(f"📊 Saved VM vs Container comparison: {save_path_comp}")

    print("✅ All plots saved in", out_dir)

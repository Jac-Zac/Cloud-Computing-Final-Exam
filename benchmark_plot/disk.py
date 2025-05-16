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

    # --- Load & parse all logs ---
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

    # 🚫 Exclude 'node local' everywhere
    full_df = full_df[~((full_df["role"] == "node") & (full_df["section"] == "local"))]

    # Melt for long form
    long_df = full_df.melt(
        id_vars=["environment", "role", "section", "kB", "reclen"],
        value_vars=metrics,
        var_name="metric",
        value_name="value",
    )

    # Determine the single, largest file size
    max_kb = long_df["kB"].max()
    long_df_big = long_df[long_df["kB"] == max_kb]

    # Save summary CSV
    csv_path = os.path.join(out_dir, "disk_summary.csv")
    long_df.to_csv(csv_path, index=False)
    print(f"📄 Saved summary CSV: {csv_path}")

    # --- 3D Plots (unchanged, still using full data) ---
    for (role, metric), grp in long_df.groupby(["role", "metric"]):
        envs = set(grp["environment"])
        secs = set(grp["section"])
        if not envs.issuperset({"vm", "container"}) or not secs.issuperset(
            {"local", "shared"}
        ):
            continue

        # Prepare mesh
        kb_vals = sorted(grp["kB"].unique())
        rl_vals = sorted(grp["reclen"].unique())
        x = np.arange(len(kb_vals))
        y = np.arange(len(rl_vals))
        kb_ix = {k: i for i, k in enumerate(kb_vals)}
        rl_ix = {r: i for i, r in enumerate(rl_vals)}

        Z = {
            (e, s): np.full((len(rl_vals), len(kb_vals)), np.nan)
            for e in ("vm", "container")
            for s in ("local", "shared")
        }
        for _, r in grp.iterrows():
            Z[(r["environment"], r["section"])][rl_ix[r["reclen"]], kb_ix[r["kB"]]] = r[
                "value"
            ]

        zmin = min(np.nanmin(m) for m in Z.values())
        zmax = max(np.nanmax(m) for m in Z.values())

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

        plt.subplots_adjust(
            left=0.08, right=0.88, top=0.88, bottom=0.08, wspace=0.25, hspace=0.25
        )
        cbar = fig.colorbar(
            surf, ax=fig.get_axes(), shrink=0.6, aspect=25, pad=0.05, location="right"
        )
        cbar.ax.tick_params(labelsize=10)
        cbar.ax.set_ylabel(metric, fontsize=12, rotation=-90, va="bottom")

        fname_3d = sanitize_filename(f"{role}_{metric}_4way") + ".png"
        save_path_3d = os.path.join(out_dir, fname_3d)
        fig.savefig(save_path_3d, dpi=300, bbox_inches="tight", pad_inches=0.2)
        plt.close(fig)
        print(f"📈 Saved: {save_path_3d}")

    # --- Bar: Local vs Shared (largest kB only) ---
    summary_ls = long_df_big.groupby(["metric", "section"])["value"].mean().unstack()
    ops = summary_ls.index.tolist()
    local_vals = summary_ls["local"].tolist()
    shared_vals = summary_ls["shared"].tolist()

    plt.figure(figsize=(14, 7))
    idx = np.arange(len(ops))
    w = 0.35
    plt.bar(idx, local_vals, width=w, label="Local", color=NORD_LOCAL)
    plt.bar(idx + w, shared_vals, width=w, label="Shared", color=NORD_SHARED)
    plt.xticks(idx + w / 2, ops, rotation=45, ha="right")
    plt.ylabel("Throughput (kB/s)")
    plt.title(f"Avg IOzone Throughput (kB={max_kb}) – Local vs Shared")
    plt.legend()
    plt.grid(axis="y", linestyle="--", alpha=0.5)
    plt.tight_layout()
    path_ls = os.path.join(out_dir, "iozone_local_vs_shared_bar_biggest.png")
    plt.savefig(path_ls, dpi=300)
    plt.close()
    print(f"📊 Saved bar comparison: {path_ls}")

    # --- Bar: VM vs Container (largest kB only) ---
    env_comp = (
        long_df_big.groupby(["environment", "section", "metric"])["value"]
        .mean()
        .reset_index()
    )
    pivot_ec = env_comp.pivot_table(
        index="metric", columns=["environment", "section"], values="value"
    )
    ops = pivot_ec.index.tolist()
    idx = np.arange(len(ops))
    w = 0.2

    def get_vals(df, env, sec):
        return df[(env, sec)].tolist() if (env, sec) in df else [0] * len(ops)

    vm_l = get_vals(pivot_ec, "vm", "local")
    vm_s = get_vals(pivot_ec, "vm", "shared")
    ct_l = get_vals(pivot_ec, "container", "local")
    ct_s = get_vals(pivot_ec, "container", "shared")

    plt.figure(figsize=(16, 8))
    plt.bar(idx - 1.5 * w, vm_l, width=w, label="VM - Local", color=NORD_VM, alpha=0.9)
    plt.bar(idx - 0.5 * w, vm_s, width=w, label="VM - Shared", color=NORD_VM, alpha=0.6)
    plt.bar(
        idx + 0.5 * w,
        ct_l,
        width=w,
        label="Container - Local",
        color=NORD_CONTAINER,
        alpha=0.9,
    )
    plt.bar(
        idx + 1.5 * w,
        ct_s,
        width=w,
        label="Container - Shared",
        color=NORD_CONTAINER,
        alpha=0.6,
    )
    plt.xticks(idx, ops, rotation=45, ha="right")
    plt.ylabel("Throughput (kB/s)")
    plt.title(f"IOzone: VM vs Container (kB={max_kb})")
    plt.legend(loc="upper left", bbox_to_anchor=(1, 1))
    plt.grid(axis="y", linestyle="--", alpha=0.5)
    plt.tight_layout()
    path_ec = os.path.join(out_dir, "iozone_vm_vs_container_biggest.png")
    plt.savefig(path_ec, dpi=300, bbox_inches="tight")
    plt.close()
    print(f"📊 Saved VM vs Container comparison: {path_ec}")

    # --- Updated Bar: Master vs Node Comparison ---
    # Aggregate data by environment, role, section
    summary_mn = (
        long_df_big.groupby(["environment", "role", "section"])["value"]
        .mean()
        .reset_index()
    )

    # Filter to relevant configurations: master local, master shared, node shared
    summary_mn = summary_mn[
        (
            (summary_mn["role"] == "master")
            & (summary_mn["section"].isin(["local", "shared"]))
        )
        | ((summary_mn["role"] == "node") & (summary_mn["section"] == "shared"))
    ]

    # Create a configuration column
    summary_mn["configuration"] = summary_mn.apply(
        lambda x: (
            f"{x['role']}_{x['section']}" if x["role"] == "master" else "node_shared"
        ),
        axis=1,
    )

    # Pivot to have environment as columns and handle missing data
    pivot_mn = (
        summary_mn.pivot_table(
            index="configuration", columns="environment", values="value", aggfunc="mean"
        )
        .reset_index()
        .fillna(0)
    )

    # Define configuration order and sort
    config_order = ["master_local", "master_shared", "node_shared"]
    pivot_mn["configuration"] = pd.Categorical(
        pivot_mn["configuration"], categories=config_order, ordered=True
    )
    pivot_mn = pivot_mn.sort_values("configuration")

    # Create plot
    plt.figure(figsize=(10, 6))
    bar_width = 0.35
    x = np.arange(len(pivot_mn))

    # Get values for containers and VMs
    container_vals = pivot_mn["container"].values
    vm_vals = pivot_mn["vm"].values

    # Plot bars
    plt.bar(
        x - bar_width / 2,
        container_vals,
        width=bar_width,
        label="Containers",
        color=NORD_CONTAINER,
        edgecolor="black",
    )
    plt.bar(
        x + bar_width / 2,
        vm_vals,
        width=bar_width,
        label="VMs",
        color=NORD_VM,
        edgecolor="black",
    )

    # Customize plot
    plt.xticks(
        x, ["Master Local", "Master Shared", "Node Shared"], rotation=45, ha="right"
    )
    plt.ylabel("Average Throughput (kB/s)")
    plt.title(
        f"Disk Performance Comparison (File Size={max_kb} kB)\nAverage Across All Metrics"
    )
    plt.legend(loc="upper left", bbox_to_anchor=(1, 1))
    plt.grid(axis="y", linestyle="--", alpha=0.5)
    plt.tight_layout()

    path_mn = os.path.join(out_dir, "master_node_comparison_avg.png")
    plt.savefig(path_mn, dpi=300, bbox_inches="tight")
    plt.close()
    print(f"📊 Saved configuration comparison: {path_mn}")

    print("✅ All plots saved in", out_dir)

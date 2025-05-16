#!/usr/bin/env python3
import os
import re
import string

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from mpl_toolkits.mplot3d import Axes3D  # noqa: F401 for 3D projection

plt.style.use("ggplot")


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
                        continue  # skip small sizes where resolution is unreliable
                    reclen = int(parts[1])
                    values = list(map(float, parts[2 : 2 + len(metrics)]))
                    entry = {"section": current, "kB": kb, "reclen": reclen}
                    entry.update({metrics[i]: values[i] for i in range(len(metrics))})
                    sections[current].append(entry)
                except ValueError:
                    continue
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

    csv_path = os.path.join(out_dir, "disk_summary.csv")
    long_df.to_csv(csv_path, index=False)
    print(f"📄 Saved summary CSV: {csv_path}")

    # 4-way 3D plots with improved layout
    for (role, metric), grp in long_df.groupby(["role", "metric"]):
        envs = set(grp["environment"])
        secs = set(grp["section"])
        if not envs.issuperset({"vm", "container"}) or not secs.issuperset(
            {"local", "shared"}
        ):
            continue

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

        # Create figure with adjusted dimensions and layout
        fig = plt.figure(figsize=(20, 18))
        fig.suptitle(
            f"Role: {role}   Metric: {metric}",
            fontsize=18,
            y=0.95,
            verticalalignment="bottom",
            weight="semibold",
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

            # Configure x-axis ticks and labels
            n_kb = len(kb_vals)
            step_x = max(1, n_kb // 6)
            ax.set_xticks(x[::step_x])
            ax.set_xticklabels(
                kb_vals[::step_x],
                rotation=35,
                ha="right",
                fontsize=10,
                rotation_mode="anchor",
            )

            # Configure y-axis ticks and labels
            n_rl = len(rl_vals)
            step_y = max(1, n_rl // 6)
            ax.set_yticks(y[::step_y])
            ax.set_yticklabels(rl_vals[::step_y], fontsize=10, ha="center", va="center")

            ax.set_xlabel("File Size (kB)", labelpad=10, fontsize=12)
            ax.set_ylabel("Record Size (bytes)", labelpad=10, fontsize=12)
            ax.set_zlabel(metric, labelpad=10, fontsize=12)

            ax.set_zlim(zmin, zmax)
            ax.view_init(elev=elev, azim=azim)
            ax.grid(True, linestyle=":", alpha=0.5)

        # Manual layout adjustment
        plt.subplots_adjust(
            left=0.08, right=0.88, top=0.88, bottom=0.08, wspace=0.25, hspace=0.25
        )

        # Add colorbar with better positioning
        cbar = fig.colorbar(
            surf, ax=fig.get_axes(), shrink=0.6, aspect=25, pad=0.05, location="right"
        )
        cbar.ax.tick_params(labelsize=10)
        cbar.ax.set_ylabel(metric, fontsize=12, rotation=-90, va="bottom")

        # Save with modified parameters
        fname = sanitize_filename(f"{role}_{metric}_4way") + ".png"
        save_path = os.path.join(out_dir, fname)
        fig.savefig(save_path, dpi=300, bbox_inches="tight", pad_inches=0.2)
        plt.close(fig)
        print(f"📈 Saved: {save_path}")

    print("✅ All plots saved in", out_dir)

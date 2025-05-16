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
    """
    Replace any non-alphanumeric characters with underscore and collapse multiples.
    """
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
            role = base.split("_")[0] if "_" in base else base
            label = f"{role} ({system[:-1]})"
            logs[label] = os.path.join(d, fname)
    return logs


def parse_iozone(lines, metrics):
    sections = {"local": [], "shared": []}
    current = None
    for ln in lines:
        ln = ln.strip()
        if "sTARTING BENCHMARK FOR: LOCAL (STANDALONE)" in ln:
            current = "local"
            continue
        if "--- IOZone shared filesystem test ---" in ln:
            current = "shared"
            continue
        if current and re.match(r"^\d+", ln):
            parts = ln.split()
            if len(parts) >= 15:
                try:
                    kb = int(parts[0])
                    reclen = int(parts[1])
                    values = list(map(float, parts[2:15]))
                    entry = {"section": current, "kB": kb, "reclen": reclen}
                    entry.update({metrics[i]: values[i] for i in range(len(metrics))})
                    sections[current].append(entry)
                except ValueError:
                    continue

    return pd.DataFrame(sections["local"]), pd.DataFrame(sections["shared"])


if __name__ == "__main__":
    results_root = "../results"
    out_dir = "plots/disk"
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

    full_records = []
    log_paths = discover_disk_logs(results_root)
    if not log_paths:
        raise SystemExit("❌ No disk logs found under containers/disk or vms/disk")

    for label, path in log_paths.items():
        role, env = label.split(" (")
        env = env.rstrip(")")
        with open(path) as f:
            lines = f.readlines()

        df_local, df_shared = parse_iozone(lines, metrics)
        for df in (df_local, df_shared):
            if df.empty:
                continue
            df["role"] = role
            df["environment"] = env
            full_records.append(df)

    full_df = pd.concat(full_records, ignore_index=True)
    long_df = full_df.melt(
        id_vars=["environment", "role", "section", "kB", "reclen"],
        value_vars=metrics,
        var_name="metric",
        value_name="value",
    )

    csv_path = os.path.join(out_dir, "disk_summary.csv")
    long_df.to_csv(csv_path, index=False)
    print(f"📄 Summary CSV saved to: {csv_path}")
    print(long_df.head())

    groups = long_df.groupby(["role", "metric", "section"])
    for (role, metric, section), grp in groups:
        envs = grp["environment"].unique()
        if set(envs) != {"vm", "container"}:
            continue

        all_kb = sorted(grp["kB"].unique())
        all_reclen = sorted(grp["reclen"].unique())
        if not all_kb or not all_reclen:
            continue

        vm_data = grp[grp["environment"] == "vm"]
        cont_data = grp[grp["environment"] == "container"]

        pivot_vm = vm_data.pivot_table(
            index="reclen", columns="kB", values="value", aggfunc="mean"
        ).reindex(index=all_reclen, columns=all_kb)
        pivot_cont = cont_data.pivot_table(
            index="reclen", columns="kB", values="value", aggfunc="mean"
        ).reindex(index=all_reclen, columns=all_kb)

        X, Y = np.meshgrid(all_kb, all_reclen)
        Z_vm = pivot_vm.values
        Z_cont = pivot_cont.values

        zmin = min(np.nanmin(Z_vm), np.nanmin(Z_cont))
        zmax = max(np.nanmax(Z_vm), np.nanmax(Z_cont))

        fig = plt.figure(figsize=(16, 8), constrained_layout=True)
        # adjust subplot margins to fit labels
        fig.subplots_adjust(left=0.05, right=0.95, bottom=0.10, top=0.90)

        # common view
        elev, azim = 25, -60

        # VM subplot
        ax1 = fig.add_subplot(1, 2, 1, projection="3d")
        surf1 = ax1.plot_surface(X, Y, Z_vm, cmap="viridis", edgecolor="none")
        ax1.set_xlim(min(all_kb), max(all_kb))
        ax1.set_ylim(min(all_reclen), max(all_reclen))
        ax1.set_zlim(zmin, zmax)
        ax1.set_xlabel("File Size (kB)", labelpad=15)
        ax1.set_ylabel("Record Size (bytes)", labelpad=15)
        ax1.set_zlabel(metric, labelpad=15)
        ax1.view_init(elev=elev, azim=azim)
        # tidy ticks
        ax1.xaxis.set_tick_params(rotation=45, pad=10)
        ax1.yaxis.set_tick_params(rotation=0, pad=10)
        ax1.zaxis.set_tick_params(rotation=0, pad=10)
        ax1.set_title(f"VM: {metric}\nRole: {role}, Section: {section}", pad=20)

        # Container subplot
        ax2 = fig.add_subplot(1, 2, 2, projection="3d")
        surf2 = ax2.plot_surface(X, Y, Z_cont, cmap="viridis", edgecolor="none")
        ax2.set_xlim(min(all_kb), max(all_kb))
        ax2.set_ylim(min(all_reclen), max(all_reclen))
        ax2.set_zlim(zmin, zmax)
        ax2.set_xlabel("File Size (kB)", labelpad=15)
        ax2.set_ylabel("Record Size (bytes)", labelpad=15)
        ax2.set_zlabel(metric, labelpad=15)
        ax2.view_init(elev=elev, azim=azim)
        ax2.xaxis.set_tick_params(rotation=45, pad=10)
        ax2.yaxis.set_tick_params(rotation=0, pad=10)
        ax2.zaxis.set_tick_params(rotation=0, pad=10)
        ax2.set_title(f"Container: {metric}\nRole: {role}, Section: {section}", pad=20)

        fig.colorbar(surf1, ax=[ax1, ax2], shrink=0.5, aspect=20)

        safe = sanitize_filename(f"{role}_{metric}_{section}_vm_vs_container")
        fname = f"disk_{safe}_compare.png"
        save_path = os.path.join(out_dir, fname)
        plt.savefig(save_path, bbox_inches="tight")
        plt.close(fig)
        print(f"📈 Saved comparison: {save_path}")

    print("✅ Done! 3D comparison plots and summary saved in", out_dir)

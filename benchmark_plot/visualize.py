import os

import matplotlib.pyplot as plt


def visualize_data(data, output_dir="plots"):
    os.makedirs(output_dir, exist_ok=True)
    plt.style.use("ggplot")

    specs = {
        "cpu": ("CPU Throughput (kEPS)", True),  # events per second, in thousands
        "mem": ("Memory Bandwidth (GiB/sec)", False),  # convert MiB/sec to GiB/sec
    }

    for metric, (ylabel, do_log) in specs.items():
        envs, vals = [], []
        for env, mets in data.items():
            v = mets.get(metric)
            if v is not None:
                envs.append(env)
                if metric == "cpu":
                    vals.append(v / 1000)  # Convert EPS to kEPS
                elif metric == "mem":
                    vals.append(v / 1024)  # Convert MiB/sec to GiB/sec

        if not vals:
            print(f"[WARN] No data for {metric}, skipping plot.")
            continue

        fig, ax = plt.subplots(figsize=(8, 5))
        bars = ax.bar(envs, vals, color=plt.cm.Set2.colors[: len(envs)])

        if do_log:
            ax.set_yscale("log")
            ax.grid(
                True, which="both", axis="y", linestyle="--", linewidth=0.7, alpha=0.7
            )
        else:
            ax.grid(axis="y", linestyle="--", linewidth=0.7, alpha=0.7)

        # Add value labels on top of bars
        for bar in bars:
            height = bar.get_height()
            unit = "kEPS" if metric == "cpu" else "GiB/s"
            ax.annotate(
                f"{height:.2f} {unit}",
                xy=(bar.get_x() + bar.get_width() / 2, height),
                xytext=(0, 5),
                textcoords="offset points",
                ha="center",
                va="bottom",
                fontsize=9,
                rotation=0,
            )

        ax.set_title(f"{ylabel} Comparison", fontsize=14, weight="bold")
        ax.set_ylabel(ylabel + (" (log scale)" if do_log else ""), fontsize=12)
        ax.set_xlabel("Environment", fontsize=12)
        plt.xticks(rotation=30, ha="right")
        plt.tight_layout()

        out_path = os.path.join(output_dir, f"{metric}_comparison.png")
        plt.savefig(out_path)
        plt.close()
        print(f"[INFO] Saved plot: {out_path}")

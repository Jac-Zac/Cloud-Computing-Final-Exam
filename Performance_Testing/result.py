#!/usr/bin/env python3
"""
Performance Test Results Analyzer

This script processes benchmark results from VM and container tests,
extracting key metrics and generating comparison graphs.
"""

import os
import re
import glob
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

# Configure plot style
sns.set_theme(style="whitegrid")
plt.rcParams.update({"font.size": 12})


def extract_sysbench_cpu_metrics(file_path):
    """Extract CPU benchmark metrics from sysbench results"""
    metrics = {}
    with open(file_path, "r") as f:
        content = f.read()
        # Extract events per second
        events_match = re.search(r"events per second:\s+(\d+\.\d+)", content)
        if events_match:
            metrics["events_per_second"] = float(events_match.group(1))

        # Extract execution time
        time_match = re.search(r"total time:\s+(\d+\.\d+)s", content)
        if time_match:
            metrics["total_time"] = float(time_match.group(1))

    return metrics


def extract_sysbench_memory_metrics(file_path):
    """Extract memory benchmark metrics from sysbench results"""
    metrics = {}
    with open(file_path, "r") as f:
        content = f.read()
        # Extract memory operations per second
        ops_match = re.search(r"transferred \(\s*(\d+\.\d+) MB/sec\)", content)
        if ops_match:
            metrics["mb_per_sec"] = float(ops_match.group(1))

    return metrics


def extract_iozone_metrics(file_path):
    """Extract disk I/O metrics from IOZone results"""
    metrics = {}
    with open(file_path, "r") as f:
        content = f.read()
        # Extract write speed
        write_match = re.search(r"Initial write\s+\d+\s+\d+\s+(\d+)", content)
        if write_match:
            metrics["write_kb_per_sec"] = int(write_match.group(1))

        # Extract read speed
        read_match = re.search(r"Read\s+\d+\s+\d+\s+(\d+)", content)
        if read_match:
            metrics["read_kb_per_sec"] = int(read_match.group(1))

        # Extract random read speed
        rand_read_match = re.search(r"Random read\s+\d+\s+\d+\s+(\d+)", content)
        if rand_read_match:
            metrics["random_read_kb_per_sec"] = int(rand_read_match.group(1))

    return metrics


def extract_iperf_metrics(file_path):
    """Extract network metrics from iperf3 results"""
    metrics = {}
    with open(file_path, "r") as f:
        content = f.read()
        # Extract bandwidth
        bw_match = re.search(r"(\d+(\.\d+)?) Mbits/sec", content)
        if bw_match:
            metrics["bandwidth_mbits"] = float(bw_match.group(1))

        # Extract retransmits (if available)
        retrans_match = re.search(r"(\d+) retransmits", content)
        if retrans_match:
            metrics["retransmits"] = int(retrans_match.group(1))

    return metrics


def extract_ping_metrics(file_path):
    """Extract ping latency metrics"""
    metrics = {}
    with open(file_path, "r") as f:
        content = f.read()
        # Extract average latency
        avg_match = re.search(
            r"min/avg/max/mdev = [\d.]+/([\d.]+)/[\d.]+/[\d.]+", content
        )
        if avg_match:
            metrics["avg_latency_ms"] = float(avg_match.group(1))

    return metrics


def extract_hpcc_metrics(file_path):
    """Extract HPC Challenge benchmark metrics"""
    metrics = {}
    with open(file_path, "r") as f:
        content = f.read()
        # Extract Gflops
        gflops_match = re.search(r"Gflops\s+=\s+(\d+\.\d+)", content)
        if gflops_match:
            metrics["gflops"] = float(gflops_match.group(1))

    return metrics


def process_result_files(results_dir):
    """Process all result files in a directory and extract metrics"""
    all_results = []

    for file_path in glob.glob(os.path.join(results_dir, "*.log")):
        file_name = os.path.basename(file_path)
        match = re.match(r"results-([^-]+)-(\d+).log", file_name)

        if match:
            target = match.group(1)
            timestamp = match.group(2)

            # Determine if this is VM, container, or host
            env_type = ""
            if "vm" in file_path:
                env_type = "VM"
            elif "container" in file_path:
                env_type = "Container"
            elif "host" in file_path:
                env_type = "Host"

            # Extract metrics from this file
            cpu_metrics = extract_sysbench_cpu_metrics(file_path)
            mem_metrics = extract_sysbench_memory_metrics(file_path)
            io_metrics = extract_iozone_metrics(file_path)
            net_metrics = extract_iperf_metrics(file_path)
            ping_metrics = extract_ping_metrics(file_path)
            hpc_metrics = extract_hpcc_metrics(file_path)

            # Combine all metrics with metadata
            result = {"target": target, "env_type": env_type, "timestamp": timestamp}
            result.update(cpu_metrics)
            result.update(mem_metrics)
            result.update(io_metrics)
            result.update(net_metrics)
            result.update(ping_metrics)
            result.update(hpc_metrics)

            all_results.append(result)

    return pd.DataFrame(all_results)


def generate_comparison_plots(df, output_dir):
    """Generate comparison plots between VM and container performance"""
    os.makedirs(output_dir, exist_ok=True)

    # 1. CPU Performance comparison
    plt.figure(figsize=(10, 6))
    sns.barplot(x="env_type", y="events_per_second", data=df)
    plt.title("CPU Performance: Events Per Second")
    plt.ylabel("Events/Second")
    plt.savefig(
        os.path.join(output_dir, "cpu_performance.png"), dpi=300, bbox_inches="tight"
    )

    # 2. Memory Performance comparison
    plt.figure(figsize=(10, 6))
    sns.barplot(x="env_type", y="mb_per_sec", data=df)
    plt.title("Memory Performance: MB/s")
    plt.ylabel("MB/Second")
    plt.savefig(
        os.path.join(output_dir, "memory_performance.png"), dpi=300, bbox_inches="tight"
    )

    # 3. Disk I/O Performance comparison
    plt.figure(figsize=(12, 8))
    io_metrics = ["write_kb_per_sec", "read_kb_per_sec", "random_read_kb_per_sec"]
    io_df = df.melt(
        id_vars=["env_type", "target"],
        value_vars=io_metrics,
        var_name="IO_Operation",
        value_name="KB_per_Second",
    )

    sns.barplot(x="env_type", y="KB_per_Second", hue="IO_Operation", data=io_df)
    plt.title("Disk I/O Performance")
    plt.ylabel("KB/Second")
    plt.savefig(
        os.path.join(output_dir, "disk_io_performance.png"),
        dpi=300,
        bbox_inches="tight",
    )

    # 4. Network Performance comparison
    plt.figure(figsize=(10, 6))
    sns.barplot(x="env_type", y="bandwidth_mbits", data=df)
    plt.title("Network Performance: Bandwidth")
    plt.ylabel("Mbits/Second")
    plt.savefig(
        os.path.join(output_dir, "network_bandwidth.png"), dpi=300, bbox_inches="tight"
    )

    # 5. Network Latency comparison
    plt.figure(figsize=(10, 6))
    sns.barplot(x="env_type", y="avg_latency_ms", data=df)
    plt.title("Network Performance: Latency")
    plt.ylabel("Average Latency (ms)")
    plt.savefig(
        os.path.join(output_dir, "network_latency.png"), dpi=300, bbox_inches="tight"
    )

    # 6. HPC Performance comparison (if available)
    if "gflops" in df.columns and not df["gflops"].isna().all():
        plt.figure(figsize=(10, 6))
        sns.barplot(x="env_type", y="gflops", data=df)
        plt.title("HPC Performance: GFLOPS")
        plt.ylabel("GFLOPS")
        plt.savefig(
            os.path.join(output_dir, "hpc_performance.png"),
            dpi=300,
            bbox_inches="tight",
        )

    # Generate summary table
    summary = df.groupby("env_type").mean().reset_index()
    summary.to_csv(os.path.join(output_dir, "performance_summary.csv"))

    print(f"Comparison plots and summary saved to {output_dir}")


def main():
    # Configure paths
    vm_results_dir = "./vm-results"
    container_results_dir = "./container-results"
    output_dir = "./analysis-results"

    # Process results
    vm_df = process_result_files(vm_results_dir)
    container_df = process_result_files(container_results_dir)

    # Combine results
    combined_df = pd.concat([vm_df, container_df])

    # Generate comparison plots
    generate_comparison_plots(combined_df, output_dir)

    # Print summary
    print("\nPerformance Summary:")
    print("===================")
    summary = combined_df.groupby("env_type").mean()
    print(summary)


if __name__ == "__main__":
    main()

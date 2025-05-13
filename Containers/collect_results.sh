#!/bin/bash
# collect-results.sh - Script to collect all benchmark results into one location

set -e  # Exit on any error

# Default output directory
OUTPUT_DIR="${1:-./benchmark-results}"
mkdir -p "$OUTPUT_DIR"

echo "📊 Collecting benchmark results to: $OUTPUT_DIR"

# Function to collect results from a VM via SSH
collect_from_vm() {
    local vm_name="$1"
    local vm_user="$2"
    local vm_ip="$3"
    
    echo "🖥️  Collecting results from VM: $vm_name ($vm_ip)..."
    
    # Create VM-specific directory
    local vm_dir="$OUTPUT_DIR/vm-$vm_name"
    mkdir -p "$vm_dir"
    
    # Use SSH to get results - requires SSH keys set up
    if ssh -o ConnectTimeout=5 "$vm_user@$vm_ip" "test -d /tmp/benchmark-results"; then
        scp -r "$vm_user@$vm_ip:/tmp/benchmark-results/*" "$vm_dir/"
        echo "✅ Successfully collected results from $vm_name"
    else
        echo "⚠️  No results found on $vm_name or SSH connection failed"
    fi
}

# Function to collect results from Docker containers
collect_from_container() {
    local container_name="$1"
    
    echo "🐳 Collecting results from container: $container_name..."
    
    # Create container-specific directory
    local container_dir="$OUTPUT_DIR/container-$container_name"
    mkdir -p "$container_dir"
    
    # Check if container exists and is running
    if docker ps -q -f name="$container_name" &>/dev/null; then
        # Copy results from container to host
        docker cp "$container_name:/tmp/benchmark-results/." "$container_dir"
        echo "✅ Successfully collected results from $container_name"
    else
        echo "⚠️  Container $container_name not found or not running"
    fi
}

# Function to collect results from local host
collect_from_host() {
    echo "🏠 Collecting results from local host..."
    
    # Create host-specific directory
    local host_dir="$OUTPUT_DIR/host-localhost"
    mkdir -p "$host_dir"
    
    # Copy local benchmark results
    if [ -d "/tmp/benchmark-results" ]; then
        cp -r /tmp/benchmark-results/* "$host_dir/"
        echo "✅ Successfully collected results from local host"
    else
        echo "⚠️  No results found on local host"
    fi
}

# Function to generate summary plot with Python
generate_plots() {
    echo "📈 Generating summary plots..."
    
    # Check if Python and matplotlib are available
    if command -v python3 &>/dev/null && python3 -c "import matplotlib" &>/dev/null; then
        # Create plots directory
        mkdir -p "$OUTPUT_DIR/plots"
        
        # Simple Python script to generate plots
        python3 - <<EOF
import os
import glob
import re
import matplotlib.pyplot as plt
import numpy as np

results_dir = "$OUTPUT_DIR"
plot_dir = os.path.join(results_dir, "plots")

# Helper function to extract values from log files
def extract_value(file_path, pattern, default=0):
    try:
        with open(file_path, 'r') as f:
            content = f.read()
            match = re.search(pattern, content)
            if match:
                return float(match.group(1))
    except Exception as e:
        print(f"Error processing {file_path}: {e}")
    return default

# Collect data
environments = ["vm", "container", "host"]
metrics = {
    "cpu": {
        "pattern": r"total time:\s+(\d+\.\d+)s",
        "title": "CPU Performance (lower is better)",
        "ylabel": "Time (seconds)"
    },
    "mem": {
        "pattern": r"transferred \((\d+\.\d+) MiB/sec\)",
        "title": "Memory Bandwidth (higher is better)",
        "ylabel": "MiB/sec"
    },
    "disk": {
        "pattern": r"write\s+(\d+)\s+\d+\s+\d+",
        "title": "Disk Write Performance (higher is better)",
        "ylabel": "KB/s"
    },
    "network": {
        "pattern": r"sender\s+\d+\.\d+-\d+\.\d+\s+sec\s+\d+(\.\d+)?\s+[GM]Bytes\s+(\d+(\.\d+)?)\s+[GM]bits/sec",
        "title": "Network Throughput (higher is better)",
        "ylabel": "Mbits/sec"
    }
}

# Process results
data = {}
for env in environments:
    data[env] = {}
    for metric in metrics:
        data[env][metric] = []
        pattern = metrics[metric]["pattern"]
        
        # Find all result files for this environment and metric
        files = glob.glob(f"{results_dir}/{env}-*/*{metric}*.log")
        for file_path in files:
            value = extract_value(file_path, pattern)
            if value > 0:  # Only add valid values
                data[env][metric].append(value)

# Generate plots
for metric, meta in metrics.items():
    plt.figure(figsize=(10, 6))
    
    # Prepare data for plotting
    labels = []
    values = []
    for env in environments:
        if data[env][metric]:
            labels.append(env)
            # Use average if multiple values
            values.append(np.mean(data[env][metric]))
    
    if not values:
        print(f"No data found for {metric}")
        continue
        
    # Create bar chart
    bars = plt.bar(labels, values)
    
    # Add values on top of bars
    for bar in bars:
        height = bar.get_height()
        plt.text(bar.get_x() + bar.get_width()/2., height,
                 f'{height:.2f}',
                 ha='center', va='bottom', rotation=0)
    
    plt.title(meta["title"])
    plt.ylabel(meta["ylabel"])
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    
    # Save plot
    plt.tight_layout()
    plt.savefig(f"{plot_dir}/{metric}_comparison.png")
    print(f"Generated plot for {metric}")

# Create summary plot
plt.figure(figsize=(12, 8))
x = np.arange(len(metrics))
width = 0.25
i = 0

for env in environments:
    env_values = []
    for metric in metrics:
        if data[env][metric]:
            # Normalize values for comparison
            values = data[env][metric]
            env_values.append(np.mean(values) / max(1, np.max([
                np.mean(data[e][metric]) if data[e][metric] else 0 
                for e in environments
            ])))
        else:
            env_values.append(0)
    
    plt.bar(x + width*i, env_values, width, label=env)
    i += 1

plt.xlabel('Metrics')
plt.ylabel('Normalized Performance')
plt.title('Performance Comparison (Normalized)')
plt.xticks(x + width, metrics.keys())
plt.legend()
plt.grid(axis='y', linestyle='--', alpha=0.7)
plt.tight_layout()
plt.savefig(f"{plot_dir}/overall_comparison.png")
print("Generated overall comparison plot")

EOF

        echo "✅ Plots generated in $OUTPUT_DIR/plots/"
    else
        echo "⚠️  Python with matplotlib not available. Skipping plot generation."
        echo "   Install with: pip install matplotlib"
    fi
}

# Main execution

# Step 1: Collect from VMs (configure your VMs here)
# Example: collect_from_vm "vm1" "ubuntu" "192.168.56.101"
# collect_from_vm "vm2" "ubuntu" "192.168.56.102"

# Read VM configuration from file or environment
VM_CONFIG_FILE="./vm_config.txt"
if [ -f "$VM_CONFIG_FILE" ]; then
    echo "📄 Reading VM configuration from $VM_CONFIG_FILE"
    while IFS=',' read -r name user ip || [ -n "$name" ]; do
        # Skip comments and empty lines
        [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
        collect_from_vm "$name" "$user" "$ip"
    done < "$VM_CONFIG_FILE"
else
    echo "ℹ️  No VM config file found. Skipping VM collection."
    echo "   Create $VM_CONFIG_FILE with format: name,user,ip"
    echo "   Example: vm1,ubuntu,192.168.56.101"
fi

# Step 2: Collect from Docker containers
echo "🔍 Looking for Docker containers..."
CONTAINERS=$(docker ps -a --format '{{.Names}}' | grep -E 'master|node-[0-9]+')
if [ -n "$CONTAINERS" ]; then
    echo "📋 Found containers: $CONTAINERS"
    for container in $CONTAINERS; do
        collect_from_container "$container"
    done
else
    echo "ℹ️  No benchmark containers found. Skipping container collection."
fi

# Step 3: Collect from local host
collect_from_host

# Step 4: Generate summary and plots
generate_plots

echo "📊 Results collection complete!"
echo "📁 All results available in: $OUTPUT_DIR"
echo "📈 Summary plots available in: $OUTPUT_DIR/plots/"

exit 0

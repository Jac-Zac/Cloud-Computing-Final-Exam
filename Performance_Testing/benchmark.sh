#!/bin/bash

set -e

TARGET=$1
MODE=$2 # "host", "container", or "vm"
ROLE=$3 # "master", "node", or "standalone"
MASTER_IP=${4:-""} # for network test (only needed on workers or standalone)

LOGDIR="/tmp/benchmark-results"
mkdir -p "$LOGDIR"

timestamp=$(date +%Y%m%d-%H%M%S)
RESULTS="$LOGDIR/results-${TARGET}-${timestamp}.log"

echo "🔧 Benchmarking $TARGET ($MODE/$ROLE)"
echo "Results saved to $RESULTS"
echo "===============================" | tee "$RESULTS"
echo "System Information:" | tee -a "$RESULTS"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)" | tee -a "$RESULTS"
echo "CPU: $(cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d':' -f2 | xargs)" | tee -a "$RESULTS"
echo "Total RAM: $(free -h | grep Mem | awk '{print $2}')" | tee -a "$RESULTS"
echo "===============================" | tee -a "$RESULTS"

# CPU benchmark
echo "👉 Running sysbench CPU test..." | tee -a "$RESULTS"
sysbench cpu --cpu-max-prime=20000 --threads=2 run | tee -a "$RESULTS"

# Memory benchmark
echo "👉 Running sysbench Memory test..." | tee -a "$RESULTS"
sysbench memory --memory-block-size=1K --memory-total-size=10G run | tee -a "$RESULTS"

# Disk benchmark
echo "👉 Running IOZone Disk test (100MB file)..." | tee -a "$RESULTS"
iozone -i 0 -i 1 -i 2 -s 100M -r 64k -f ./iozone.tmp | tee -a "$RESULTS"
rm -f ./iozone.tmp

# Network benchmark
if [[ "$ROLE" == "master" ]]; then
    echo "👉 Starting iperf3 server (waiting for client)..." | tee -a "$RESULTS"
    nohup iperf3 -s > "$LOGDIR/iperf3-server.log" 2>&1 &
    echo "iperf3 server running in background." | tee -a "$RESULTS"
elif [[ "$ROLE" == "node" || "$ROLE" == "standalone" ]]; then
    if [[ -z "$MASTER_IP" ]]; then
        echo "⚠️ Please provide MASTER_IP for network test." | tee -a "$RESULTS"
    else
        echo "👉 Running iperf3 client to $MASTER_IP..." | tee -a "$RESULTS"
        iperf3 -c "$MASTER_IP" | tee -a "$RESULTS"
        
        # Test network latency using ping
        echo "👉 Testing network latency to $MASTER_IP..." | tee -a "$RESULTS"
        ping -c 10 "$MASTER_IP" | tee -a "$RESULTS"
    fi
else
    echo "⚠️ Unknown role: $ROLE. Skipping network test." | tee -a "$RESULTS"
fi

# Run HPL test if present (HPC Challenge Benchmark)
if command -v hpcc &> /dev/null; then
    if [[ -f "./HPL.dat" ]]; then
        echo "👉 Running HPC Challenge benchmark..." | tee -a "$RESULTS"
        # Only capture essential HPL output for easier analysis
        hpcc | grep -E "T/V|WR|Gflops" | tee -a "$RESULTS"
    else
        echo "⚠️ HPL.dat not found. Skipping HPC benchmark." | tee -a "$RESULTS"
    fi
else
    echo "⚠️ HPCC command not found. Skipping HPC benchmark." | tee -a "$RESULTS"
fi

echo "✅ Benchmark complete for $TARGET."
echo "Full results available at $RESULTS"

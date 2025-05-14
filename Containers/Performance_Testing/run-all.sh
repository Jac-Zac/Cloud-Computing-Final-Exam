#!/bin/bash
set -e

show_help() {
  cat << EOF
Usage: $(basename "$0") TARGET ROLE MASTER_IP [BENCHMARKS]

Run selected or all benchmarks (cpu, mem, disk, net, hpl) on the specified TARGET.

Arguments:
  TARGET      The target machine or environment to run benchmarks on
  ROLE        The role of the node (e.g., master, worker)
  MASTER_IP   The IP address of the master node
  BENCHMARKS  (Optional) Comma-separated list of benchmarks to run (e.g., cpu,mem)
              If not provided, all benchmarks will be run.

Example:
  $(basename "$0") node01 master 192.168.1.10 cpu,mem
EOF
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
  exit 0
fi

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Error: Invalid number of arguments."
  show_help
  exit 1
fi

TARGET=$1
ROLE=$2
MASTER_IP=$3
SCRIPTS_DIR="$(dirname "$0")"

if [[ -n "$4" ]]; then
  IFS=',' read -ra BENCHMARKS <<< "$4"
else
  BENCHMARKS=(cpu mem disk net hpl)
fi

for BENCH in "${BENCHMARKS[@]}"; do
  SCRIPT="$SCRIPTS_DIR/bin/${BENCH}-benchmark.sh"
  if [[ -x "$SCRIPT" ]]; then
    "$SCRIPT" "$TARGET" "$ROLE" "$MASTER_IP"
  else
    echo "Warning: Benchmark script '$SCRIPT' not found or not executable. Skipping."
  fi
done

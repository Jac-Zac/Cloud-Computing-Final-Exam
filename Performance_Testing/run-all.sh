#!/bin/bash
set -e

show_help() {
  cat << EOF
Usage: $(basename "$0") TARGET MODE ROLE MASTER_IP [BENCHMARKS]

Run selected or all benchmarks (cpu, mem, disk, net, hpl) on the specified TARGET.

Arguments:
  TARGET      The target machine or environment to run benchmarks on
  MODE        The mode of operation (e.g., test, production)
  ROLE        The role of the node (e.g., master, worker)
  MASTER_IP   The IP address of the master node
  BENCHMARKS  (Optional) Comma-separated list of benchmarks to run (e.g., cpu,mem)
              If not provided, all benchmarks will be run.

Example:
  $(basename "$0") node01 test master 192.168.1.10 cpu,mem
EOF
}

# Show help if requested or if arguments are missing
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
  exit 0
fi

if [[ $# -lt 4 || $# -gt 5 ]]; then
  echo "Error: Invalid number of arguments."
  show_help
  exit 1
fi

TARGET=$1
MODE=$2
ROLE=$3
MASTER_IP=$4
SCRIPTS_DIR="$(dirname "$0")"

# Default to all benchmarks if not specified
if [[ -n "$5" ]]; then
  IFS=',' read -ra BENCHMARKS <<< "$5"
else
  BENCHMARKS=(cpu mem disk net hpl)
fi

for BENCH in "${BENCHMARKS[@]}"; do
  SCRIPT="$SCRIPTS_DIR/${BENCH}-benchmark.sh"
  if [[ -x "$SCRIPT" ]]; then
    "$SCRIPT" "$TARGET" "$MODE" "$ROLE" "$MASTER_IP"
  else
    echo "Warning: Benchmark script '$SCRIPT' not found or not executable. Skipping."
  fi
done


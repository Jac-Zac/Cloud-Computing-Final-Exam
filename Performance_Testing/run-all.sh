#!/bin/bash
set -e

show_help() {
  cat << EOF
Usage: $(basename "$0") TARGET MODE ROLE MASTER_IP

Run a series of benchmarks (cpu, mem, disk, net, hpl) on the specified TARGET.

Arguments:
  TARGET     The target machine or environment to run benchmarks on
  MODE       The mode of operation (e.g., test, production)
  ROLE       The role of the node (e.g., master, worker)
  MASTER_IP  The IP address of the master node

Example:
  $(basename "$0") node01 test master 192.168.1.10

This script will sequentially execute the following benchmark scripts:
  cpu-benchmark.sh
  mem-benchmark.sh
  disk-benchmark.sh
  net-benchmark.sh
  hpl-benchmark.sh
EOF
}

# Show help if requested or if arguments are missing
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
  exit 0
fi

if [[ $# -ne 4 ]]; then
  echo "Error: Invalid number of arguments."
  show_help
  exit 1
fi

TARGET=$1
MODE=$2
ROLE=$3
MASTER_IP=$4

SCRIPTS_DIR="$(dirname "$0")"

for BENCH in cpu mem disk net hpl; do
  "$SCRIPTS_DIR/${BENCH}-benchmark.sh" "$TARGET" "$MODE" "$ROLE" "$MASTER_IP"
done

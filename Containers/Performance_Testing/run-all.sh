#!/bin/bash
set -e

show_help() {
  cat << EOF
Usage: $(basename "$0") [BENCHMARKS] [MPI_HOSTFILE]

Run selected or all benchmarks (cpu, mem, disk, net, hpl).

Arguments:
  BENCHMARKS     (Optional) Comma-separated list of benchmarks (default: all)
  MPI_HOSTFILE   (Optional) Path to an MPI hostfile for distributed execution

Example:
  $(basename "$0") cpu,mem hosts.txt
  $(basename "$0") disk
EOF
}

# Parse args
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
  exit 0
fi

SCRIPTS_DIR="$(dirname "$0")"
BENCHMARKS="cpu,mem,disk"
MPI_HOSTFILE=""

# Handle optional args
if [[ $# -ge 1 ]]; then
  if [[ "$1" == *","* || "$1" =~ ^(cpu|mem|disk)$ ]]; then
    BENCHMARKS="$1"
    shift
  fi
fi

if [[ $# -ge 1 ]]; then
  MPI_HOSTFILE="$1"
fi

IFS=',' read -ra BENCH_LIST <<< "$BENCHMARKS"

run_benchmark() {
  BENCH=$1
  SCRIPT="$SCRIPTS_DIR/bin/${BENCH}-benchmark.sh"

  if [[ ! -x "$SCRIPT" ]]; then
    echo "Warning: $SCRIPT not found or not executable. Skipping."
    return
  fi

  if [[ "$BENCH" == "cpu" || "$BENCH" == "mem" ]]; then
    if [[ -n "$MPI_HOSTFILE" && -f "$MPI_HOSTFILE" ]]; then
      echo "Running $BENCH benchmark with MPI..."
      mpirun --hostfile "$MPI_HOSTFILE" "$SCRIPT" &
    else
      "$SCRIPT" &
    fi
  else
    "$SCRIPT"
  fi
}

# Run selected benchmarks
for BENCH in "${BENCH_LIST[@]}"; do
  run_benchmark "$BENCH"
done

# Wait for parallel ones
wait

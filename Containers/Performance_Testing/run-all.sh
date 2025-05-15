#!/bin/bash
set -e

show_help() {
  cat << EOF
Usage: $(basename "$0") [BENCHMARKS] [MPI_HOSTFILE]

Run selected or all benchmarks (cpu, mem, net).

Arguments:
  BENCHMARKS     (Optional) Comma-separated list of benchmarks (default: all)
  MPI_HOSTFILE   (Optional) Path to an MPI hostfile for distributed execution

Examples:
  $(basename "$0") cpu,mem hosts.txt
  $(basename "$0") net hosts.txt
EOF
}

# Validate benchmark names
is_valid_benchmark() {
  [[ "$1" =~ ^(cpu|mem|net|hpl)$ ]]
}

# Parse help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
  exit 0
fi

SCRIPTS_DIR="$(dirname "$0")"
BENCHMARKS="cpu,mem,net,hpl"
MPI_HOSTFILE=""

# Handle optional args
if [[ $# -ge 1 ]]; then
  if [[ "$1" == *","* ]]; then
    BENCHMARKS="$1"
    shift
  elif is_valid_benchmark "$1"; then
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
  elif [[ "$BENCH" == "net" ]]; then
    if [[ -n "$MPI_HOSTFILE" && -f "$MPI_HOSTFILE" ]]; then
      MASTER_IP=$(head -n 1 "$MPI_HOSTFILE" | awk '{print $1}')
      echo "Running network benchmark from nodes to master ($MASTER_IP)..."
      mpirun --hostfile "$MPI_HOSTFILE" "$SCRIPT" "$MASTER_IP" &
      echo "Running network benchmark on master targeting itself..."
      "$SCRIPT" "127.0.0.1" &
    else
      echo "Running network benchmark locally (no MPI hostfile)..."
      "$SCRIPT" "127.0.0.1" &
    fi
  else
    "$SCRIPT"
  fi
}

# Run selected benchmarks
for BENCH in "${BENCH_LIST[@]}"; do
  if is_valid_benchmark "$BENCH"; then
    run_benchmark "$BENCH"
  else
    echo "Warning: Invalid benchmark name '$BENCH'. Skipping."
  fi
done

wait

#!/bin/bash
source ./common.sh "$@"

log_info "-> Running HPL benchmark if available..."

if command -v hpcc &> /dev/null; then
  if [[ -f "./HPL.dat" ]]; then
    if [[ -f "./mpi-hostfile" ]]; then
      log_info "-> Running distributed HPL using mpirun..."
      mpirun -np 4 --hostfile mpi-hostfile hpcc | grep -E "T/V|WR|Gflops" | tee -a "$RESULTS"
    else
      log_info "-> Running local HPL benchmark..."
      hpcc | grep -E "T/V|WR|Gflops" | tee -a "$RESULTS"
    fi
  else
    log_info "Missing HPL.dat."
  fi
else
  log_info "HPCC not installed."
fi

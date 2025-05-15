#!/bin/bash
source "$(dirname "$0")/common.sh"

log_info "⚙️ Running CPU benchmarks"

log_info "-> Sysbench (max prime = 30k)"
sysbench cpu --cpu-max-prime=30000 --threads=2 run | tee -a "$RESULTS"

log_info "-> Stress-ng: basic"
stress-ng --cpu 2 --timeout 60s --metrics-brief | tee -a "$RESULTS"

log_info "-> Stress-ng: matrix multiplication"
stress-ng --cpu 2 --cpu-method matrixprod --timeout 60s --metrics-brief | tee -a "$RESULTS"

log_success "✅ CPU benchmark complete"

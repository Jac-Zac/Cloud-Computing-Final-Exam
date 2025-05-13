#!/bin/bash
source "$(dirname "$0")/common.sh" "$@"

log_info "⚙️ Running CPU benchmarks"

log_info "- Sysbench (max prime = 50k)"
sysbench cpu --cpu-max-prime=50000 --threads=4 run | tee -a "$RESULTS"

log_info "- Stress-ng: basic"
stress-ng --cpu 4 --timeout 60s --metrics-brief | tee -a "$RESULTS"

log_info "- Stress-ng: matrix multiplication"
stress-ng --cpu 4 --cpu-method matrixprod --timeout 60s --metrics-brief | tee -a "$RESULTS"

log_success "✅ CPU benchmark complete"

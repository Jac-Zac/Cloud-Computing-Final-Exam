#!/bin/bash
source "$(dirname "$0")/common.sh"

log_info "-> Running sysbench memory test (500M)..."
sysbench memory --memory-block-size=1M --threads=2 --memory-total-size=500M run | tee -a "$RESULTS"

log_info "-> Running stress-ng memory test (2 workers, 1 min)..."
stress-ng --vm 2 --vm-bytes 500M --timeout 60s --metrics-brief | tee -a "$RESULTS"

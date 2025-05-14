#!/bin/bash
source ./common.sh "$@"

log_info "-> Running sysbench memory test (10G)..."
sysbench memory --memory-block-size=1K --memory-total-size=10G run | tee -a "$RESULTS"

log_info "-> Running stress-ng memory test (2 workers, 2 min)..."
stress-ng --vm 2 --vm-bytes 1G --timeout 120s --metrics-brief | tee -a "$RESULTS"

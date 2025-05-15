#!/bin/bash
source "$(dirname "$0")/common.sh"

TARGET_IP="$1"  # Pass target IP as an argument

# Network benchmark if TARGET_IP provided
if [[ -n "$TARGET_IP" ]]; then
  log_info "Starting network benchmark against target: $TARGET_IP"

  log_info "--- iperf3 bandwidth test ---"
  iperf3 -c "$TARGET_IP" -t 30 2>&1 | tee -a "$RESULTS"

  log_info "--- ping latency test ---"
  ping -c 50 -i 0.2 "$TARGET_IP" 2>&1 | tee -a "$RESULTS"

  log_success "✅ Network benchmark complete"
else
  log_warn "No TARGET_IP provided, skipping network benchmark."
fi

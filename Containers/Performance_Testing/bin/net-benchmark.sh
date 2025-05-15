#!/bin/bash
source "$(dirname "$0")/common.sh"

if [[ "$ROLE" == "master" ]]; then
  log_info "Starting iperf3 server on master"
  nohup iperf3 -s > /dev/null 2>&1 &
  # log_success "iperf3 server running in background"
else
  if [[ -z "$MASTER_IP" ]]; then
    log_error "MASTER_IP not provided. Cannot run network test."
    exit 1
  fi
  log_info "Running iperf3 client to $MASTER_IP"
  iperf3 -c "$MASTER_IP" | tee -a "$RESULTS"

  log_info "Running ping latency test"
  ping -c 10 "$MASTER_IP" | tee -a "$RESULTS"

  log_success "✅ Network benchmark complete"
fi

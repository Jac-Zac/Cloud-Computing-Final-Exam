#!/bin/bash
source ./common.sh "$@"

if [[ "$ROLE" == "master" ]]; then
  log_info "👉 Starting iperf3 server..."
  nohup iperf3 -s > "$LOGDIR/iperf3-server.log" 2>&1 &
  log_info "iperf3 server running in background."
elif [[ "$ROLE" == "node" || "$ROLE" == "standalone" ]]; then
  if [[ -z "$MASTER_IP" ]]; then
    log_info "⚠️ MASTER_IP not provided."
  else
    log_info "👉 Running iperf3 client to $MASTER_IP..."
    iperf3 -c "$MASTER_IP" | tee -a "$RESULTS"

    log_info "👉 Testing network latency to $MASTER_IP..."
    ping -c 10 "$MASTER_IP" | tee -a "$RESULTS"
  fi
else
  log_info "⚠️ Unknown role: $ROLE"
fi

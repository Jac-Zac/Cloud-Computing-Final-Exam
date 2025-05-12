#!/bin/bash
LOGDIR="/tmp/benchmark-results"
mkdir -p "$LOGDIR"
timestamp=$(date +%Y%m%d-%H%M%S)

TARGET=${1:-"unknown"}
MODE=${2:-"unknown"}
ROLE=${3:-"standalone"}
MASTER_IP=${4:-""}
RESULTS="$LOGDIR/results-${TARGET}-${timestamp}.log"

function log_info {
  echo "$1" | tee -a "$RESULTS"
}

log_info "🔧 Benchmarking $TARGET ($MODE/$ROLE)"
log_info "Results saved to $RESULTS"
log_info "==============================="
log_info "System Info:"
log_info "OS: $(grep PRETTY_NAME /etc/os-release | cut -d'\"' -f2)"
log_info "CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)"
log_info "Total RAM: $(free -h | awk '/Mem:/ {print $2}')"
log_info "==============================="


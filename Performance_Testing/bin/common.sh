#!/bin/bash
set -e

LOGDIR="./logs"
RESULTDIR="./results"
mkdir -p "$LOGDIR" "$RESULTDIR"

timestamp=$(date +%Y%m%d-%H%M%S)
TARGET=${1:-"unknown"}
MODE=${2:-"unknown"}
ROLE=${3:-"standalone"}
MASTER_IP=${4:-""}
RESULTS="${RESULTDIR}/results-${TARGET}-${timestamp}.log"

# Color codes
GREEN="\e[32m"
BLUE="\e[34m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

function log_info {
  echo -e "${BLUE}[$(date +%T)] $1${RESET}" | tee -a "$RESULTS"
}

function log_success {
  echo -e "${GREEN}[$(date +%T)] $1${RESET}" | tee -a "$RESULTS"
}

function log_warn {
  echo -e "${YELLOW}[$(date +%T)] $1${RESET}" | tee -a "$RESULTS"
}

function log_error {
  echo -e "${RED}[$(date +%T)] $1${RESET}" | tee -a "$RESULTS"
}

log_info "🔧 Starting benchmark for: $TARGET ($MODE/$ROLE)"
log_info "📄 Output will be saved to: $RESULTS"
log_info "==============================="
log_info "🖥️  System Info:"
log_info "OS: $(grep PRETTY_NAME /etc/os-release | cut -d'\"' -f2)"
log_info "CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)"
log_info "RAM: $(free -h | awk '/Mem:/ {print $2}')"
log_info "==============================="

#!/bin/bash
set -e

RESULTDIR="./results"
mkdir -p "$RESULTDIR"

timestamp=$(date +%Y%m%d-%H%M%S)
TARGET=${1:-"unknown"}
ROLE=${2:-"standalone"}
MASTER_IP=${3:-""}
RESULTS="${RESULTDIR}/results-${TARGET}-${timestamp}.log"

# Disable color if not running in terminal
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

log_info()    { echo -e "${BLUE}[$(date +%T)] $1${RESET}" | tee -a "$RESULTS"; }
log_success() { echo -e "${GREEN}[$(date +%T)] $1${RESET}" | tee -a "$RESULTS"; }
log_warn()    { echo -e "${YELLOW}[$(date +%T)] $1${RESET}" | tee -a "$RESULTS"; }
log_error()   { echo -e "${RED}[$(date +%T)] $1${RESET}" | tee -a "$RESULTS"; }

# Collect system info, macOS and Linux support
get_os() {
  if [[ -f /etc/os-release ]]; then
    grep PRETTY_NAME /etc/os-release | cut -d'"' -f2
  elif [[ "$(uname)" == "Darwin" ]]; then
    sw_vers -productName && sw_vers -productVersion
  else
    uname -a
  fi
}

get_cpu() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sysctl -n machdep.cpu.brand_string
  elif [[ -f /proc/cpuinfo ]]; then
    grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs
  else
    echo "Unknown CPU"
  fi
}

get_ram() {
  if command -v free &>/dev/null; then
    free -h | awk '/Mem:/ {print $2}'
  elif [[ "$(uname)" == "Darwin" ]]; then
    mem_bytes=$(sysctl -n hw.memsize)
    echo "$((mem_bytes / 1024 / 1024)) MB"
  else
    echo "Unknown RAM"
  fi
}

log_info "Starting benchmark for: $TARGET ($ROLE)"
log_info "Output will be saved to: $RESULTS"
log_info "==============================="
log_info "System Info:"
log_info "OS:  $(get_os)"
log_info "CPU: $(get_cpu)"
log_info "RAM: $(get_ram)"
log_info "==============================="

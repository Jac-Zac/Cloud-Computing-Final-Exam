#!/bin/bash
#!/bin/bash
source ./common.sh "$@"

log_info "👉 Running sysbench CPU test (intensive)..."
sysbench cpu --cpu-max-prime=50000 --threads=2 run | tee -a "$RESULTS"

log_info "👉 Running stress-ng CPU stress test (2 min, 2 workers)..."
stress-ng --cpu 2 --timeout 120s --metrics-brief | tee -a "$RESULTS"


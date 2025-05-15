#!/bin/bash

source "$(dirname "$0")/common.sh"

OUTPUT_FILE="${RESULTS:-disk_test_results.log}"
LOCAL_FILE="./iozone_local.tmp"
SHARED_MOUNT="/shared"
SHARED_FILE="$SHARED_MOUNT/iozone_shared.tmp"

# log_info "--- IOZone local filesystem test ---"
iozone -a -f "$LOCAL_FILE" 2>&1 | tee -a "$OUTPUT_FILE"
rm -f "$LOCAL_FILE"

if [[ -d "$SHARED_MOUNT" ]]; then
  log_info "--- IOZone shared filesystem test ---"
  iozone -a -f "$SHARED_FILE" 2>&1 | tee -a "$OUTPUT_FILE"
  rm -f "$SHARED_FILE"

else
  log_info "⚠️  No shared filesystem found at $SHARED_MOUNT. Skipping shared tests."
fi


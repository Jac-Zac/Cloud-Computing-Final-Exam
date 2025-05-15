#!/bin/bash
set -e

source ./common.sh

OUTPUT_FILE="${RESULTS:-disk_test_results.log}"
LOCAL_FILE="./iozone_local.tmp"
SHARED_MOUNT="/shared"
SHARED_FILE="$SHARED_MOUNT/iozone_shared.tmp"

log_info "--- IOZone local filesystem test ---"
iozone -i 0 -i 1 -i 2 -s 100M -r 64k -f "$LOCAL_FILE" 2>&1 | tee -a "$OUTPUT_FILE"
rm -f "$LOCAL_FILE"

log_info "--- FIO local I/O test ---"
fio --name=localtest --ioengine=libaio --rw=randwrite --bs=4k --numjobs=16 \
    --size=1G --runtime=10s --time_based --unlink=1 2>&1 | tee -a "$OUTPUT_FILE"

if [[ -d "$SHARED_MOUNT" ]]; then
  log_info "--- IOZone shared filesystem test ---"
  iozone -i 0 -i 1 -i 2 -s 100M -r 64k -f "$SHARED_FILE" 2>&1 | tee -a "$OUTPUT_FILE"
  rm -f "$SHARED_FILE"

  log_info "--- FIO shared I/O test ---"
  fio --name=sharedtest --directory="$SHARED_MOUNT" --ioengine=libaio --rw=randwrite \
      --bs=4k --numjobs=16 --size=1G --runtime=10s --time_based --unlink=1 2>&1 | tee -a "$OUTPUT_FILE"
else
  log_info "⚠️  No shared filesystem found at $SHARED_MOUNT. Skipping shared tests."
fi


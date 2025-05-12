#!/bin/bash
source ./common.sh "$@"

MOUNT_POINT="./iozone.tmp"

log_info "👉 Checking disk mount info..."
MOUNT_INFO=$(df -T "$PWD" | tail -1)
FS_TYPE=$(echo "$MOUNT_INFO" | awk '{print $2}')
MOUNT_SRC=$(echo "$MOUNT_INFO" | awk '{print $1}')
log_info "Filesystem: $FS_TYPE from $MOUNT_SRC"

if [[ "$FS_TYPE" == "nfs" || "$MOUNT_SRC" == *":/"* ]]; then
  log_info "⚠️ NFS/shared filesystem detected!"
else
  log_info "✅ Local filesystem detected."
fi

log_info "👉 Running IOZone disk benchmark (100MB file)..."
iozone -i 0 -i 1 -i 2 -s 100M -r 64k -f "$MOUNT_POINT" | tee -a "$RESULTS"

rm -f "$MOUNT_POINT"

#!/bin/bash
source ./common.sh "$@"

# Get mount point for testing
MOUNT_POINT="${5:-./iozone.tmp}"  # Use 5th parameter if provided, otherwise default
SHARED_MOUNT="${5:-/shared}"      # Check if shared filesystem exists

log_info "👉 Checking disk mount info..."
MOUNT_INFO=$(df -T "$PWD" | tail -1)
FS_TYPE=$(echo "$MOUNT_INFO" | awk '{print $2}')
MOUNT_SRC=$(echo "$MOUNT_INFO" | awk '{print $1}')
log_info "Filesystem: $FS_TYPE from $MOUNT_SRC"

# Test local filesystem
if [[ "$FS_TYPE" == "nfs" || "$MOUNT_SRC" == *":/"* ]]; then
  log_info "⚠️ NFS/shared filesystem detected!"
else
  log_info "✅ Local filesystem detected."
fi

log_info "👉 Running IOZone on local filesystem (100MB file)..."
iozone -i 0 -i 1 -i 2 -s 100M -r 64k -f "$MOUNT_POINT" | tee -a "$RESULTS"
rm -f "$MOUNT_POINT"

# Test shared filesystem if it exists
if [[ -d "$SHARED_MOUNT" ]]; then
  log_info "👉 Found shared mount point at $SHARED_MOUNT, testing shared filesystem..."
  SHARED_INFO=$(df -T "$SHARED_MOUNT" | tail -1)
  SHARED_FS_TYPE=$(echo "$SHARED_INFO" | awk '{print $2}')
  SHARED_MOUNT_SRC=$(echo "$SHARED_INFO" | awk '{print $1}')
  log_info "Shared filesystem: $SHARED_FS_TYPE from $SHARED_MOUNT_SRC"
  
  SHARED_TEST_FILE="$SHARED_MOUNT/iozone_shared.tmp"
  
  log_info "👉 Running IOZone on shared filesystem (100MB file)..."
  iozone -i 0 -i 1 -i 2 -s 100M -r 64k -f "$SHARED_TEST_FILE" | tee -a "$RESULTS"
  
  # Clean up test file
  rm -f "$SHARED_TEST_FILE"
  
  # If this is the master node, test concurrent filesystem access
  if [[ "$ROLE" == "master" ]]; then
    log_info "👉 Testing shared filesystem concurrent access (master)..."
    
    # Create test files for each expected node
    for i in {1..3}; do
      echo "Test file for concurrent access from master" > "$SHARED_MOUNT/test_concurrent_$i.txt"
    done
    
    # Start monitoring
    log_info "👉 Monitoring shared filesystem for 30 seconds..."
    iostat -xm 5 6 | grep -E "$SHARED_MOUNT|Device" | tee -a "$RESULTS" &
  elif [[ "$ROLE" == "node" && -n "$MASTER_IP" ]]; then
    log_info "👉 Testing shared filesystem concurrent access (node)..."
    
    # Wait for master to create test files
    sleep 5
    
    # Read and write to shared test files
    for i in {1..3}; do
      if [[ -f "$SHARED_MOUNT/test_concurrent_$i.txt" ]]; then
        cat "$SHARED_MOUNT/test_concurrent_$i.txt" >> "$SHARED_MOUNT/test_concurrent_response_$i.txt"
        echo "Response from node $TARGET" >> "$SHARED_MOUNT/test_concurrent_response_$i.txt"
        
        # Create some additional I/O load
        dd if=/dev/zero of="$SHARED_MOUNT/iotest_$TARGET_$i.dat" bs=1M count=50 conv=fsync 2>> "$RESULTS"
      fi
    done
  fi
else
  log_info "ℹ️ No shared filesystem found at $SHARED_MOUNT. Skipping shared filesystem tests."
fi

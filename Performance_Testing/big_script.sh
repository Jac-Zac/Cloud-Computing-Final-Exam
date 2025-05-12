#!/bin/bash

# Strict mode
set -euo pipefail # Exit on error, unset var, pipe failure

# --- Script Configuration & Parameters ---
TARGET_NAME="${1?Usage: $0 <target_name> <mode> <role> [master_ip]}" # e.g., vm1, container1, localhost
MODE="${2?Usage: $0 <target_name> <mode> <role> [master_ip]}"        # e.g., vm, container, host
ROLE="${3?Usage: $0 <target_name> <mode> <role> [master_ip]}"        # e.g., master, node, standalone
MASTER_IP="${4:-}" # Optional, but required if ROLE is 'node'

# --- Environment Configuration ---
# Directory where results will be saved temporarily within the VM/container/host run
RESULTS_DIR="./results"
# Final collected results directory (assumed on host) structure is ~/benchmark-results/<target_name>/
LOG_PREFIX="${RESULTS_DIR}/${TARGET_NAME}_${MODE}_${ROLE}"
HOST_LIST_FILE="${RESULTS_DIR}/hostfile.mpi" # For MPI hpcc run

# Resource definitions (as per exercise spec)
NUM_CPUS=2
MEM_SIZE_GB=2
MEM_SIZE_MB=$((MEM_SIZE_GB * 1024))
MEM_SIZE_BYTES=$((MEM_SIZE_MB * 1024 * 1024))

# iperf3 config
IPERF_DURATION=10 # seconds
IPERF_SERVER_PID_FILE="${RESULTS_DIR}/iperf_server.pid"

# HPCC/HPL config
HPL_DAT_FILE="./HPL.dat" # Assumed to be in the same dir as run-all.sh
# Calculate total MPI processes. Assumes 1 master + (number of nodes).
# THIS IS A SIMPLIFICATION - YOU NEED TO ADJUST BASED ON ACTUAL NODE COUNT
# For a simple Master + 1 Node setup:
TOTAL_MPI_NODES=2 # Default assumption master + 1 node, ADJUST IF DIFFERENT
TOTAL_MPI_PROCS=$((TOTAL_MPI_NODES * NUM_CPUS)) # e.g., 2 nodes * 2 CPUs = 4 processes

# --- Helper Functions ---
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] - $*" | tee -a "${LOG_PREFIX}_summary.log"
}

cleanup() {
    log "Running cleanup..."
    # Stop iperf3 server if PID file exists (only master should have created it)
    if [[ -f "$IPERF_SERVER_PID_FILE" ]]; then
        log "Stopping iperf3 server (PID: $(cat $IPERF_SERVER_PID_FILE))..."
        kill "$(cat $IPERF_SERVER_PID_FILE)" &>/dev/null || log "iperf3 server already stopped or failed to kill."
        rm -f "$IPERF_SERVER_PID_FILE"
    fi
    # Add other cleanup if needed
    log "Cleanup complete."
}

# --- Main Execution ---

# Setup trap for cleanup on exit/interrupt
trap cleanup EXIT INT TERM

# Ensure results directory exists
mkdir -p "$RESULTS_DIR"

log "--- Starting Benchmark Run ---"
log "Target: $TARGET_NAME | Mode: $MODE | Role: $ROLE"
log "Master IP (if node): $MASTER_IP"
log "CPUs: $NUM_CPUS | Memory: ${MEM_SIZE_GB}GB"
log "Results Dir (local): $RESULTS_DIR"
log "------------------------------"

# --- Individual Benchmarks ---

log "Running CPU benchmarks..."
./cpu-benchmark.sh "$NUM_CPUS" "${LOG_PREFIX}_cpu.log"
log "CPU benchmarks complete."

log "Running Memory benchmarks..."
# Pass memory size in MB or bytes as needed by your mem-benchmark script
./mem-benchmark.sh "$NUM_CPUS" "$MEM_SIZE_MB" "${LOG_PREFIX}_mem.log"
log "Memory benchmarks complete."

log "Running Disk I/O benchmarks..."
# Define appropriate file size (e.g., 1GB fits comfortably in 2GB RAM)
DISK_TEST_FILE_SIZE_MB=1024
./disk-benchmark.sh "$DISK_TEST_FILE_SIZE_MB" "${LOG_PREFIX}_disk.log"
# Add NFS logic here if implementing
log "Disk I/O benchmarks complete."

# --- Role-Dependent Benchmarks ---

# Network Test (iperf3)
NETWORK_LOG="${LOG_PREFIX}_network.log"
log "--- Network Test (iperf3) ---"
case "$ROLE" in
    master)
        log "Starting iperf3 server in background..."
        # Start server, capture PID, log output to network log
        iperf3 -s -D --pidfile "$IPERF_SERVER_PID_FILE" --logfile "$NETWORK_LOG"
        if [[ -f "$IPERF_SERVER_PID_FILE" ]]; then
             log "iperf3 server started (PID: $(cat $IPERF_SERVER_PID_FILE)). Waiting for client(s)."
        else
             log "ERROR: Failed to start iperf3 server." >&2
             # Decide if this is fatal; maybe continue other tests?
        fi
        # Server will be killed during cleanup trap
        ;;
    node)
        if [[ -z "$MASTER_IP" ]]; then
            log "ERROR: Master IP required for node role in network test." >&2
            exit 1 # Cannot run client without server IP
        fi
        log "Waiting a few seconds for iperf3 server on $MASTER_IP..."
        sleep 5 # Give server time to start
        log "Running iperf3 client against $MASTER_IP..."
        # Run client, use JSON output for easier parsing, append to log
        if ! iperf3 -c "$MASTER_IP" -t "$IPERF_DURATION" -J >> "$NETWORK_LOG"; then
            log "ERROR: iperf3 client failed to connect or run against $MASTER_IP." >&2
            # Consider if this error should halt the script
        else
            log "iperf3 client test complete."
        fi
        ;;
    standalone)
        log "Skipping network test in standalone mode."
        ;;
    *)
        log "ERROR: Unknown role '$ROLE'." >&2
        exit 1
        ;;
esac
log "--- Network Test End ---"


# HPC Test (hpcc with MPI)
HPCC_LOG="${LOG_PREFIX}_hpc.log"
log "--- HPC Test (hpcc) ---"
if [[ ! -f "$HPL_DAT_FILE" ]]; then
     log "WARNING: $HPL_DAT_FILE not found. Skipping HPCC benchmark."
else
    case "$ROLE" in
        master)
            log "Preparing for HPCC run (Master)..."
            # --- CRITICAL: MPI Host Configuration ---
            # You MUST configure how MPI finds the nodes.
            # Option A: Manually create hostfile.mpi
            # Example: Create this file BEFORE running the script on master.
            # Contents of hostfile.mpi (adjust IPs/names & slots):
            # 192.168.56.101 slots=2 # Master VM/Container
            # 192.168.56.102 slots=2 # Node1 VM/Container
            # ... add other nodes

            if [[ ! -f "$HOST_LIST_FILE" ]]; then
                log "ERROR: MPI host file '$HOST_LIST_FILE' not found. Cannot run distributed HPCC." >&2
                log "Skipping HPCC benchmark. Please create '$HOST_LIST_FILE'."
            else
                log "Found MPI host file '$HOST_LIST_FILE'. Contents:"
                cat "$HOST_LIST_FILE" | tee -a "${LOG_PREFIX}_summary.log"
                # Calculate total processes based on hostfile content if possible, or use pre-calculated TOTAL_MPI_PROCS
                log "Attempting to run HPCC with $TOTAL_MPI_PROCS processes across nodes defined in $HOST_LIST_FILE..."
                # Ensure HPL.dat P*Q matches TOTAL_MPI_PROCS!
                if mpirun --hostfile "$HOST_LIST_FILE" -np "$TOTAL_MPI_PROCS" hpcc >> "$HPCC_LOG" 2>&1; then
                     log "HPCC benchmark run initiated by master seems complete."
                else
                     log "ERROR: HPCC benchmark run failed. Check MPI setup and $HPCC_LOG for details." >&2
                     # Check ssh connectivity between nodes, mpi installation, paths.
                fi
            fi
            ;;
        node)
            log "HPCC Node: Ready. Ensuring sshd is running (manual check recommended)."
            # Node just needs to be reachable by MPI from the master.
            # Check if sshd is running: `systemctl status ssh` or `service ssh status`
            # Ensure passwordless SSH *from* master *to* this node is set up if using SSH for MPI transport.
            log "Node waiting for master to initiate HPCC job..."
            ;;
        standalone)
            log "Running HPCC benchmark locally (Standalone)..."
            # Run hpcc only on this machine using its allocated cores
            if mpirun -np "$NUM_CPUS" localhost hpcc >> "$HPCC_LOG" 2>&1; then
                 log "HPCC benchmark complete (Standalone)."
            else
                 log "ERROR: HPCC benchmark failed locally. Check $HPCC_LOG." >&2
            fi
            ;;
        *)
            log "ERROR: Unknown role '$ROLE'." >&2
            # Already handled in network section, but double check
            ;;
    esac
fi
log "--- HPC Test End ---"


# --- Finalization ---
log "------------------------------"
log "Benchmark Run Script Finished: $TARGET_NAME ($MODE, $ROLE)"
log "Results logs are located in: $RESULTS_DIR"
log "Remember to collect results from this directory to the host machine's central location."
log "--- End of Run ---"

# Trap will execute cleanup function automatically on exit

exit 0

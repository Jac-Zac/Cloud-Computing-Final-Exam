#!/bin/bash
TARGET=$1
MODE=$2
ROLE=$3
MASTER_IP=$4

./cpu-benchmark.sh "$TARGET" "$MODE" "$ROLE" "$MASTER_IP"
./mem-benchmark.sh "$TARGET" "$MODE" "$ROLE" "$MASTER_IP"
./disk-benchmark.sh "$TARGET" "$MODE" "$ROLE" "$MASTER_IP"
./net-benchmark.sh "$TARGET" "$MODE" "$ROLE" "$MASTER_IP"
./hpl-benchmark.sh "$TARGET" "$MODE" "$ROLE" "$MASTER_IP"

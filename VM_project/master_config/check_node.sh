#!/bin/bash

# Default number of nodes
n=${1:-4}

# Build the node list
nodes=(master)
for i in $(seq 1 "$n"); do
  num=$(printf "%02d" "$i")   # Always 2 digits, zero-padded
  nodes+=("node-$num")
done

# Node status monitoring script
echo "Checking node status (up to node-$(printf "%02d" "$n")):"
for node in "${nodes[@]}"; do
  echo -n "$node: "
  ping -c 1 -W 1 "$node" >/dev/null && echo "UP" || echo "DOWN"
done

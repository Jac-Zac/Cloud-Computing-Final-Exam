#!/bin/bash

# Default number of nodes
n=${1:-9}

# Build the node list
nodes=(master)
for i in $(seq -w 1 "$n"); do
  nodes+=("node-$i")
done

# Node status monitoring script
echo "Checking node status (up to node-${n}):"
for node in "${nodes[@]}"; do
  echo -n "$node: "
  ping -c 1 -W 1 "$node" >/dev/null && echo "UP" || echo "DOWN"
done

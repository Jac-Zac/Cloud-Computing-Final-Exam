#!/bin/bash
set -e

echo "📦 Installing dependencies..."
sudo apt update
sudo apt install -y sysbench iozone3 iperf3 mpich hpcc stress-ng

echo "✅ Dependencies installed."

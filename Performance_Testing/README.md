# Cloud Computing Performance Testing Guide

This guide provides a complete implementation plan for comparing performance between virtual machines and containers.

## Part 1: VM Performance Testing

### 1. Environment Setup

Create a complete VM environment:

```bash
# Set up master node
./setup_node.sh master 3022

# Set up worker nodes
./setup_node.sh node-02 4022
./setup_node.sh node-03 5022
```

### 2. Install Benchmarking Tools

SSH into your master node and install the required benchmarking tools:

```bash
ssh -p 3022 user01@127.0.0.1

# On master node:
sudo apt update
sudo apt install -y sysbench iozone3 iperf3 build-essential libopenmpi-dev openmpi-bin
```

#### Installing HPC Challenge Benchmark

```bash
# Install HPCC
sudo apt-get update
sudo apt-get install -y hpcc

# Check installation
which hpcc
```

### 3. Create a Benchmark Script

Create a benchmarking script on your master node that will run tests. You can use the `benchmark.sh` script you already have:

```bash
# Copy your benchmark script to master
scp -P 3022 benchmark.sh user01@127.0.0.1:~/benchmark.sh

# Make it executable
ssh -p 3022 user01@127.0.0.1 "chmod +x ~/benchmark.sh"
```

### 4. Configure HPL for High-Performance Linpack

Create an HPL.dat configuration file for the master node:

```bash
scp -P 3022 HPL.dat user01@127.0.0.1:~/HPL.dat
```

### 5. Run VM Performance Tests

On the master node, run the benchmark tests:

```bash
# Run CPU benchmark on master
./benchmark.sh master vm master

# Start network benchmark server on master
iperf3 -s &

# Connect to node-02 and run benchmarks there
ssh node-02
./benchmark.sh node-02 vm node master

# Connect to node-03 and run benchmarks there
ssh node-03
./benchmark.sh node-03 vm node master

# Run HPL benchmark on master
hpcc
```

## Part 2: Container Performance Testing

### 1. Build and Run Docker Containers

```bash
# Build containers (from directory containing Dockerfile, compose.yaml, etc.)
docker-compose build

# Start the container cluster
docker-compose up -d

# Verify containers are running
docker-compose ps
```

### 2. Run Container Performance Tests

```bash
# Run benchmark on master container
docker exec master /app/benchmark.sh master container master

# Run benchmark on worker nodes
docker exec node-01 /app/benchmark.sh node-01 container node master
docker exec node-02 /app/benchmark.sh node-02 container node master

# Run HPL benchmark on master container
docker exec master hpcc
```

## Part 2: Test Host Machine Performance (Optional)

```bash
# Install benchmarking tools on host
sudo apt update
sudo apt install -y sysbench iozone3 iperf3 build-essential libopenmpi-dev openmpi-bin

# Run benchmarks on host
./benchmark.sh localhost host standalone
```

## Part 3: Collecting and Analyzing Results

### 1. Collecting Results

```bash
# From host, collect VM results
scp -P 3022 user01@127.0.0.1:/tmp/benchmark-results/* ./vm-results/

# Collect container results
docker cp master:/tmp/benchmark-results ./container-results-master
docker cp node-01:/tmp/benchmark-results ./container-results-node01
docker cp node-02:/tmp/benchmark-results ./container-results-node02
```

### 2. Analyzing Results

Create a comparison table focusing on these key metrics:

1. **CPU Performance**:
   - Events per second from sysbench
   - FLOPS from HPL

2. **Disk I/O Performance**:
   - Read/Write throughput from IOZone
   - Random access performance

3. **Network Performance**:
   - Bandwidth between nodes (iperf3)
   - Latency between nodes

### 3. Report Template

#### Introduction
- Brief description of the test environment
- Hardware specifications of host machine
- VM and container configurations

#### Methodology
- Description of tools used
- Test parameters and scenarios
- Resource allocation for VMs and containers

#### Results
- CPU performance comparison (table and graphs)
- Disk I/O performance comparison (table and graphs)
- Network performance comparison (table and graphs)

#### Analysis
- Performance overhead of virtualization vs. containerization
- Impact of resource constraints
- Scalability observations
- File system performance differences

#### Conclusion
- Summary of findings
- Recommendations for different workloads
- Limitations of the testing methodology

## Troubleshooting Tips

### VM Network Issues
If VMs cannot communicate:
```bash
# Check network configuration
ip addr show
cat /etc/netplan/50-cloud-init.yaml

# Verify DNS resolution
nslookup master
cat /etc/resolv.conf
```

### Container Network Issues
If containers cannot communicate:
```bash
# Check Docker network
docker network inspect hpcnet

# Test connectivity between containers
docker exec master ping node-01
```

### Benchmark Tool Issues
If benchmarks fail to run:
```bash
# Check tool installation
which sysbench iozone hpcc iperf3

# Verify script permissions
ls -la /app/benchmark.sh
```

## Advanced Testing Options

### Testing with Different VM Configurations
Experiment with different VM configurations:
- CPU allocation (1, 2, 4 cores)
- Memory allocation (1GB, 2GB, 4GB)
- Different virtual disk types (VDI, VMDK)

### Testing with Different Container Resource Limits
Modify your compose.yaml to test different container limits:
```yaml
deploy:
  resources:
    limits:
      cpus: "1.0"  # Try 1.0, 2.0, 4.0
      memory: 1g   # Try 1g, 2g, 4g
```

### Testing NFS Performance
For VMs:
```bash
# Mount NFS on workers
sudo mount master:/shared /mnt/nfs

# Test NFS performance
iozone -i 0 -i 1 -i 2 -s 100M -r 64k -f /mnt/nfs/test.dat
```

For containers, add NFS volume to compose.yaml and test similarly.

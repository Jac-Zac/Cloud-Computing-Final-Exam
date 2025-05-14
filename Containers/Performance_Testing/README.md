# Cloud Computing Benchmark Suite

This benchmark suite provides tools to compare performance between virtual machines (VMs), containers, and host systems, with special attention to distributed workloads and shared filesystems.

## Overview

The benchmark suite tests:

- CPU performance
- Memory performance
- Disk I/O (local and shared filesystems)
- Network performance
- HPC workloads (using MPI)

## Setup Instructions

### Prerequisites

- For VMs: VirtualBox, VMware, or similar virtualization software
- For containers: Docker and Docker Compose
- For host testing: MacOS (M4 chip) with homebrew

### Installation

#### On macOS Host:

```bash
# Install dependencies
brew install sysbench stress-ng iozone iperf3
```

#### For VMs/Containers:

The benchmark scripts will automatically install dependencies using:

```bash
./install-deps.sh
```

## Directory Structure

```
benchmark-suite/
├── scripts/
│   ├── cpu-benchmark.sh
│   ├── mem-benchmark.sh
│   ├── disk-benchmark.sh
│   ├── net-benchmark.sh
│   ├── hpl-benchmark.sh
│   ├── common.sh
│   ├── install-deps.sh
│   ├── run-all.sh
│   └── collect-results.sh  # New script to gather results
├── docker/
│   ├── Dockerfile
│   └── docker-compose.yml
├── config/
│   └── mpi-hostfile.template
└── results/
    └── plots/
```

## Running Benchmarks

### 1. Virtual Machine Testing

Set up 2-3 VMs with 2 vCPUs, 2GB RAM each. Ensure they can communicate via network.

On the master VM:

```bash
./run-all.sh vm1 vm master
```

On each worker VM:

```bash
./run-all.sh vm2 vm node master-ip-address
```

### 2. Container Testing

Using the provided `docker-compose.yml`:

```bash
# Start the containers
docker-compose up -d

# Run benchmarks on master
docker exec -it master bash
cd /benchmark
./run-all.sh container-master container master

# Run benchmarks on nodes
docker exec -it node-01 bash
cd /benchmark
./run-all.sh container-node1 container node master

# Repeat for other nodes
```

### 3. Host Testing

```bash
# On Mac M4 with resource limits
cpulimit -l 200 ./run-all.sh localhost host standalone
```

## Shared Filesystem Testing

The suite automatically detects NFS/shared filesystems during disk benchmarks. If using the `/shared` mount point:

```bash
# Run specific test on shared filesystem
./disk-benchmark.sh target mode role master-ip /shared
```

## Collecting Results

After running benchmarks on all systems, use the collection script:

```bash
./collect-results.sh output_directory
```

This will:

1. Gather results from all VMs via SSH (configure in script)
2. Copy results from Docker containers
3. Include host results
4. Generate comparison plots

## Docker Compose Configuration

The provided `docker-compose.yml` correctly:

- Limits each container to 2 CPUs and 2GB RAM
- Sets up a shared volume (`hpc-shared`) mounted at `/shared`
- Creates a bridge network for inter-container communication
- Designates container roles (master/worker)

## Understanding the Results

Results are organized by:

- Environment type (VM/container/host)
- Node name
- Benchmark type

Plots show comparisons between different environments for each metric, helping identify performance differences between virtualization methods.

## Customization

- Edit `common.sh` to adjust log directories and common functions
- Modify individual benchmark scripts to change test parameters
- Update `docker-compose.yml` to adjust container resources

## Troubleshooting

- If MPI tests fail, check that hostfiles are correctly generated
- For network tests, verify firewall rules allow iperf3 traffic
- For shared filesystem tests, ensure mount points exist and have correct permissions

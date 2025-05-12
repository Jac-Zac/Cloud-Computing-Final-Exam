# Cloud Computing Performance Testing Guide

This guide provides a complete implementation plan for comparing performance between virtual machines (VMs), containers, and optionally, the host system.

---

## Part 1: VM Performance Testing

### 1. Environment Setup

- Create 2-3 virtual machines (Ubuntu recommended).
- Allocate each VM with 2 vCPUs and 2GB RAM.
- Set up a shared or bridged network so VMs can communicate.
- Ensure passwordless SSH is set up between host and VMs, or prepare to use `scp`.

### 2. Install Benchmark Suite

On each VM, run the following:

```bash
sudo apt update && sudo apt install -y sysbench stress-ng iozone3 iperf3 hpcc
```

Or use the provided script:

```bash
./install-deps.sh
```

### 3. Copy Benchmark Scripts

Use `scp` to copy scripts from your Mac host to each VM:

```bash
scp -r ./cloud-benchmark user@<vm-ip>:/home/user/
```

### 4. Run Benchmarks

SSH into the VM and execute:

```bash
./run-all.sh vm1 vm node <master-ip-if-needed>
```

After the run, copy results back to your Mac:

```bash
scp user@<vm-ip>:/tmp/benchmark-results/* ~/benchmark-results/vm1/
```

Repeat for each VM.

---

## Part 2: Container Performance Testing

### 1. Docker Environment Setup

- Install Docker and Docker Compose on your Mac.
- Use the provided `docker-compose.yml` to spin up containers.
- Logs will be saved to a mounted host directory.

```bash
docker-compose up -d
```

### 2. Run Benchmarks Inside Containers

Attach to a container:

```bash
docker exec -it node1 bash
```

Execute the script:

```bash
./run-all.sh container1 container node <master-ip-if-needed>
```

Results will be automatically saved to `./benchmark-results` on your Mac.

---

## Part 3: Host System Testing (Optional)

To test your Mac (host) with same resource limits:

```bash
sudo systemd-run --scope -p CPUQuota=200% -p MemoryLimit=2G ./run-all.sh localhost host standalone
```

Or use `cpulimit` if `systemd-run` is not available:

```bash
cpulimit -l 200 -z ./run-all.sh localhost host standalone
```

Logs will be saved in `~/benchmark-results`.

---

## Running All Benchmarks

Use the `run-all.sh` script to automate all tests:

```bash
./run-all.sh <target-name> <mode> <role> [master-ip]
```

Examples:

```bash
./run-all.sh vm1 vm master
./run-all.sh container1 container node 172.28.1.10
./run-all.sh localhost host standalone
```

Each test will call individual scripts:

- `cpu-benchmark.sh`
- `mem-benchmark.sh`
- `disk-benchmark.sh`
- `network-benchmark.sh`
- `hpc-benchmark.sh`

---

## Log Collection

All logs are saved under:

```bash
~/benchmark-results/
```

VMs: use `scp` to collect logs.

Containers: logs are mounted directly to `./benchmark-results` on your host.

---

## Tools Used

- `sysbench`: CPU and memory stress testing
- `stress-ng`: Advanced stress testing
- `iozone`: Disk I/O performance
- `iperf3`: Network throughput testing
- `hpcc`: HPC-style benchmarking (on VMs or containers with MPI)

---

## Plotting and Analysis

1. Install Python and matplotlib:

```bash
pip install matplotlib pandas
```

2. Use the provided script `plot-results.py` to generate plots:

```bash
python3 plot-results.py ~/benchmark-results/
```

3. The script will parse logs and generate CPU, memory, disk, and network performance comparisons across:

- VM
- Container
- Host

4. Charts will be saved under `~/benchmark-results/plots/`

---

## Deliverables

- Full logs in `~/benchmark-results/`
- Summary plots in `~/benchmark-results/plots/`
- Final report comparing performance across environments
- Observations on virtualization overhead and efficiency

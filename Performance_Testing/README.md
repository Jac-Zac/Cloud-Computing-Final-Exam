# ☁️ Cloud Computing Performance Testing Guide

This guide provides a comprehensive implementation plan for benchmarking and comparing performance across **virtual machines (VMs)**, **containers**, and the **host system**. It automates CPU, memory, disk, network, and HPC-style testing using open-source tools.

---

## 📆 Project Structure

```
.
├── bin/
│   ├── common.sh
│   ├── cpu-benchmark.sh
│   ├── disk-benchmark.sh
│   ├── mem-benchmark.sh
│   ├── net-benchmark.sh
│   └── hpl-benchmark.sh
├── run-all.sh
├── install-deps.sh
├── docker-compose.yml
└── README.md
```

---

## 🚀 Part 1: VM Performance Testing

### 1. Environment Setup

- Create 2-3 Ubuntu virtual machines (e.g., via VirtualBox or cloud provider).
- Allocate 2 vCPUs and 2GB RAM per VM.
- Use a bridged or host-only adapter to ensure network connectivity.
- Set up passwordless SSH or prepare to use `scp` for file transfers.

### 2. Install Benchmark Dependencies

On each VM:

```bash
sudo apt update && sudo apt install -y sysbench stress-ng iozone3 iperf3 hpcc
```

Or use:

```bash
./install-deps.sh
```

### 3. Copy Benchmark Scripts

From your host:

```bash
scp -r ./cloud-benchmark user@<vm-ip>:/home/user/
chmod +x /home/user/cloud-benchmark/bin/*.sh
```

### 4. Run Benchmarks

SSH into each VM:

```bash
cd cloud-benchmark
./run-all.sh vm1 vm node <master-ip-if-any>
```

After completion:

```bash
scp user@<vm-ip>:/tmp/benchmark-results/* ~/benchmark-results/vm1/
```

Repeat for all VMs.

---

## 🚫 Part 2: Container Performance Testing

### 1. Docker Setup

- Install Docker and Docker Compose.
- Launch test containers:

```bash
docker-compose up -d
```

### 2. Run Benchmarks in Containers

Attach and run:

```bash
docker exec -it node1 bash
./run-all.sh container1 container node <master-ip-if-any>
```

Results are saved to `./benchmark-results` on your host via Docker volume.

---

## 💻 Part 3: Host System Testing (Optional)

To simulate same VM/container resource limits:

```bash
sudo systemd-run --scope -p CPUQuota=200% -p MemoryLimit=2G ./run-all.sh localhost host standalone
```

If `systemd-run` is not available:

```bash
cpulimit -l 200 -z ./run-all.sh localhost host standalone
```

Logs will be saved to `~/benchmark-results`.

---

## 📊 Running All Benchmarks

Use the main runner:

```bash
./run-all.sh <target> <mode> <role> [master-ip]
```

Examples:

```bash
./run-all.sh vm1 vm master
./run-all.sh container1 container node 172.28.1.10
./run-all.sh localhost host standalone
```

Benchmarks include:

- `cpu-benchmark.sh`
- `mem-benchmark.sh`
- `disk-benchmark.sh`
- `net-benchmark.sh`
- `hpl-benchmark.sh`

---

## 📃 Log Collection

All benchmark logs are stored under:

```bash
~/benchmark-results/
```

- VMs: use `scp` to collect logs.
- Containers: logs are automatically mounted to host.

---

## ⚖️ Tools Used

- `sysbench`: CPU and memory benchmarking
- `stress-ng`: Stress testing CPU, memory
- `iozone`: Disk I/O benchmarks
- `iperf3`: Network throughput
- `hpcc`: HPC-style floating point benchmarks

---

## 📊 Plotting & Analysis

1. Install dependencies:

```bash
pip install matplotlib pandas
```

2. Run:

```bash
python3 plot-results.py ~/benchmark-results/
```

3. Generates CPU, memory, disk, and network comparison charts for:

- VM
- Container
- Host

Saved to:

```bash
~/benchmark-results/plots/
```

---

## 📄 Deliverables

- Raw logs in `~/benchmark-results/`
- Visual plots in `~/benchmark-results/plots/`
- Summary report comparing environments
- Key insights into virtualization overhead and efficiency

Here's a simplified and merged **Markdown tutorial** version of your original Typst benchmarking document, combined with your more concise suite documentation. The goal is to provide a clear, user-friendly guide with a focus on benchmarking tools and execution, while trimming excess detail and code repetition.

---

# Cloud Computing Benchmark Suite

This guide provides tools and instructions to benchmark and compare system performance across **virtual machines (VMs)**, **containers**, and **host systems**. It emphasizes distributed workloads, shared filesystems, and resource isolation.

---

## 🧪 What This Benchmarks

- **CPU Performance** (`hpcc`, `sysbench`)
- **Memory Performance** (`sysbench`, `stress-ng`)
- **Disk I/O** (local & shared) with `IOZone`
- **Network Performance** (`iperf3`)
- **HPC Workloads** using MPI (`hpcc`)

---

## 🔧 Environment Setup

The benchmarking suite supports three configurations:

- **Host Machine**: macOS (M4 chip)
- **Containers**: Docker + Docker Compose (1 master + 2 workers, simulated HPC cluster)
- **VMs**: VirtualBox VMs (2 vCPUs, 2GB RAM)

Inter-node communication and shared filesystems are enabled via Docker bridge networks and volumes (e.g., mounted at `/shared`).

---

## 📁 Project Structure

```
├── bin/
│   ├── cpu-benchmark.sh
│   ├── disk-benchmark.sh
│   ├── mem-benchmark.sh
│   ├── net-benchmark.sh
│   └── common.sh
├── configs/
│   ├── hpccinf.txt
│   └── mpi-hostfile
├── results/
├── install-deps.sh
├── run-all.sh
└── README.md
```

---

## ⚙️ Installation

### On macOS (Host)

```bash
brew install sysbench stress-ng iozone iperf3
```

### On VMs/Containers

Dependencies are installed via the provided script:

```bash
./install-deps.sh
```

---

## 🚀 How to Run Benchmarks

### 1. CPU Benchmark

#### HPL (High Performance Linpack)

Used for floating-point performance on distributed systems:

```bash
sudo apt install hpcc
mpirun.openmpi -np 6 -hostfile configs/mpi-hostfile hpcc
```

Edit `hpccinf.txt` to increase problem size if desired.

#### Sysbench CPU (Single Node)

```bash
sysbench cpu --cpu-max-prime=30000 --threads=2 run
```

Or run across all nodes:

```bash
./run-all.sh cpu configs/mpi-hostfile
```

---

### 2. Memory Benchmark

```bash
sysbench memory --memory-total-size=500M --memory-block-size=1M --threads=2 run
stress-ng --vm 2 --vm-bytes 500M --timeout 60s --metrics-brief
```

Or distributed:

```bash
./run-all.sh mem configs/mpi-hostfile
```

---

### 3. Disk I/O Benchmark

Performs tests on both local and shared filesystems:

```bash
./disk-benchmark.sh
```

Results are logged, and shared mount at `/shared` is used if available.

---

### 4. Network Benchmark

Run `iperf3` in client/server modes across nodes:

```bash
# On server node
iperf3 -s

# On client node
iperf3 -c <server-ip>
```

Or use the bundled script:

```bash
./run-all.sh net configs/mpi-hostfile
```

---

### 5. HPC Workloads

The `hpcc` MPI test also evaluates realistic HPC workloads:

- Adjust `configs/hpccinf.txt` for test size
- Results and plots can be found in the GitHub repo:
  [benchmark_plot/plots/hpcc](https://github.com/Jac-Zac/Cloud-Computing-Final-Exam/tree/main/benchmark_plot/plots/hpcc)

---

## 🐳 Container Deployment (Docker Compose)

Using the provided `docker-compose.yml`:

```bash
docker-compose up -d
```

This sets up:

- 1 master + 2 worker containers
- 2 vCPUs, 2GB RAM per container
- Shared volume at `/shared`
- Inter-container networking

Then inside the master container:

```bash
docker exec -it master bash
cd /benchmark
./run-all.sh container-master container master
```

Repeat similar steps for workers.

---

## 💡 Tips & Notes

- Scripts in `bin/` are modular and reusable.
- You can mix and match benchmarks or run all with `./run-all.sh <cpu|mem>`.
- Shared filesystem performance depends on NFS or Docker volume configurations.

---

## 📊 Results

Most test results are logged into the `results/` directory and can be visualized using custom plotting scripts (see GitHub).

> 📁 Repository: [Jac-Zac/Cloud-Computing-Final-Exam](https://github.com/Jac-Zac/Cloud-Computing-Final-Exam)

---

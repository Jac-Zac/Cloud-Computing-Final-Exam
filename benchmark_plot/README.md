## README Update for Benchmark Visualization Scripts

This repository provides Python scripts for parsing, analyzing, and visualizing benchmark results for CPU, memory, disk, and HPCC (High-Performance Computing Challenge) tests across different environments (host, VMs, containers).

---

**Directory Structure**

- `cpu_mem.py`: Parses CPU and memory benchmark logs, computes averages, and generates comparative bar plots.
- `disk.py`: Processes IOzone disk benchmark logs, summarizes results, and creates 3D surface plots comparing VMs and containers.
- `hpcc.py`: Extracts and visualizes key metrics from HPCC benchmark outputs for VMs and containers.

---

## Usage

**1. Prerequisites**

- Python 3.x
- Required packages: `matplotlib`, `pandas`, `numpy`
- Benchmark results should be organized under a `../results` directory, structured as follows:

```bash
results
├── containers
│   ├── cpu
│   │   └── cpu.log
│   ├── disk
│   │   ├── master_disk.log
│   │   └── node_disk.log
│   ├── mem
│   │   └── mem.log
│   ├── net
│   │   ├── master_node.log
│   │   ├── node_master.log
│   │   └── node_node.log
│   └── hpccoutf.txt
├── host
│   ├── cpu
│   │   └── cpu.log
│   ├── mem
│   │   └── mem.log
│   └── net
│       └── net.log
└── vms
    ├── cpu
    │   └── cpu.log
    ├── disk
    │   ├── master.log
    │   └── node.log
    ├── mem
    │   └── mem.log
    ├── net
    │   ├── master_node.log
    │   ├── node_master.log
    │   └── node_node.log
    └── hpccoutf.txt
```

**2. Running the Scripts**

- **CPU and Memory:**

  > Run `cpu_mem.py` to parse logs, generate summary CSV, and create bar plots for CPU and memory metrics.

  ```bash
  python cpu_mem.py
  ```

  - Output:
    - `plots/benchmark_results.csv`
    - Bar plots in `plots/cpu/` and `plots/memory/`

- **Disk Benchmarks:**

  > Run `disk.py` to process IOzone logs, summarize results, and generate 3D comparison plots.

  ```bash
  python disk.py
  ```

  - Output:
    - `plots/disk/disk_summary.csv`
    - 3D surface plots in `plots/disk/`

- **HPCC Benchmarks:**

  > Run `hpcc.py` to extract and visualize key HPCC metrics.

  ```bash
  python hpcc.py
  ```

  - Output:
    - Plots in `plots/hpcc/`

---

## Features

- **Automated Parsing:**
  Each script automatically discovers and parses relevant log files based on environment and benchmark type.
- **Flexible Visualization:**
  - CPU/memory: Comparative bar charts highlight best/worst performers.
  - Disk: 3D surface plots compare performance across file and record sizes for VMs and containers.
  - HPCC: Extracts and visualizes important metrics for in-depth HPC analysis.
- **Summary Outputs:**
  All scripts generate CSV summaries for further analysis and reproducibility.

---

## Example Plots

- Bar charts comparing events/sec, latency, and memory throughput across environments.
- 3D surface plots for disk read/write performance by file and record size.
- HPCC metric visualizations for bandwidth, latency, and computational throughput.

#import "@preview/hei-synd-report:0.1.1": *
#import "/metadata.typ": *
#pagebreak()

= Benchmarks

// I installed all the dependencies
// all the procedure has been run both on the VMs and on containers' cluster. 

// Sysbench

To evaluate the various environments (virtual machines, dock containers and host systems) performance, a comprehensive benchmarking technique was used.

Benchmarks mainly focused on the following domains: 
- CPU performance using `hpcc` and `sysbench`
- Memory performance using `sysbench`
- Disk I/O (both local and over shared file systems) with `IOZone`
- Network performance using `iperf3`
- High Performance Computing (HPC) workloads using MPI.
The aim was to compare performance and resource isolation among these key environments. 

== Environment configuration

The framework was deployed across the following environments: a host machine (macOS M4 in this case), three docker containers (a master and two workers) that simulate a HPC cluster, and multiple virtual machines with 2 vCPUs and 2 GB RAM. 

Docker compose enabled the containerised cluster management. Thanks to a bridge network it established inter-container communication. Also, via a docker-managed volume mounted at `/shared`, filesystem access was enabled. 

== Installation
The software dependencies, sysbench, hpcc, iozone, and iperf3, are installed using the following command:

```bash
brew install sysbench stress-ng iozone iperf3
```

On virtual machines and containers, dependencies are automatically installed by using: 

```bash
./install-deps.sh
```

At this point the project structure has evolved in something like this:

```bash
.
├── Dockerfile
├── compose.yaml
├── entrypoint.sh
├── benchmark/
│   ├── run-all.sh
│   ├── configs/
│   │   └── mpi-hostfile
│   ├── results/
│   │   ├── master/
│   │   ├── node-01/
│   │   └── node-02/
│   └── shared/
├── bin/
│   ├── cpu-benchmark.sh
│   ├── mem-benchmark.sh
│   ├── disk-benchmark.sh
│   └── net-benchmark.sh
└── install-deps.sh
```

== CPU benchmarking

=== High-Performance Linpack (HPL)
The HPL benchmark is part of the `hpcc` package, its execution aims at assessing the floating-point computation performance across the different cluster nodes. 

Firstly, we have to verify that all nodes are updated and that `hpcc` is installed. This can be done with the following command:

```bash
sudo apt update
sudo apt install hpcc
```

After, it is important to check if `openmpi` is available on all nodes using:

```bash
apt list --installed | grep mpi
```

At this point, a hostfile that lists all node hostnames is created with the name `cluster_hosts`. 

The benchmark is run with default parameters to check the setup integrity:

```bash
mpirun.openmpi -np 3 -hostfile cluster_hosts hpcc
```
 
Due to unspecified network interface, a warning is encountered, which can be solved by setting the interface:

```bash
mpirun.openmpi -mca btl_tcp_if_include enp0s8 -np 3 -hostfile cluster_hosts hpcc
```

Finally, the benchmark was configured for a larger problem size with the example input file (`_hpccinf.txt`) customised as follows:

```bash
11520          Ns         (problem size)
64 128 192 256 NBs        (block sizes)
1              Ps         (process grid dimension P)
3              Qs         (process grid dimension Q)
```

Thanks to this configuration, the matrix size was divisible by the block sizes, leading to an improvement in both load balancing and performance results accuracy. 

=== Sysbench - CPU

In order to complement the HPL results, `sysbench` was used to benchmark the single-node CPU performance. Though this method lacks distributed execution support, comparative results between nodes were done. 

Firstly, this tool was installed and its version was verified:

```bash
mpirun.openmpi -np 3 -hostfile cluster_hosts sysbench --version
```

Next, a wrapper script was implemented to run the tool automatically:

```bash
#!/bin/bash
# run_sysbench.sh
if [ -z "$1" ]; then
  echo "Usage: $0 <cpu-max-prime>"
  exit 1
fi

sysbench --test=cpu --cpu-max-prime="$1" run > ~/sysbench_maxprime_"$1"
```

This script was then made available to all worker nodes through the use of scp and made executable in the cluster by using:

```bash
mpirun -np 3 --hostfile cluster_hosts chmod +x ~/run_sysbench.sh
mpirun -np 3 --hostfile cluster_hosts ./run_sysbench.sh 10000
```

== Memory performance

Similarly to what done for the CPU performance evaluation, memory benchmarks will also be performed using `sysbench`:

```bash
#!/bin/bash
# run_sysbench_mem.sh
BLOCK_SIZE=${1:-1M}
TOTAL_SIZE=${2:-1G}

sysbench --test=memory \
  --memory-block-size=$BLOCK_SIZE \
  --memory-total-size=$TOTAL_SIZE \
  run > ~/sysbench_mem_${BLOCK_SIZE}_${TOTAL_SIZE}
```

After copying the script and making it executable for each node, memory performance is evaluated by doing:
```bash
mpirun -np 3 --hostfile cluster_hosts ./run_sysbench_mem.sh 1M 24G
```

== Disk I/O performance

`IOZone` is used to evaluate the disk performance. After installing `iozone3`, we have to check its version. This can be done with the following command:
```bash
mpirun -np 3 --hostfile cluster_hosts iozone -v | grep Version
```

The master node, acting as the NFS server, is analysed with tests on both the local `/tmp` directory and shared `/shared` volume by using:

```bash
iozone -a -I -s 102400 -r 1024 -f /tmp/iozone.tmp > iozone_master_local
iozone -a -I -s 102400 -r 1024 -f /shared/iozone_nfs_master.tmp > iozone_master_nfs
```

Identical tests are performed on the client node 

```bash
iozone -a -I -s 102400 -r 1024 -f /tmp/iozone.tmp > iozone_node_local
iozone -a -I -s 102400 -r 1024 -f /shared/data/iozone_nfs_node.tmp > iozone_node_nfs
```

// not sure you want to write this:
// As expected, the NFS-based write performance was lower than local storage due to network latency.


== Network performance

To test inter-node bandwidth and latency, we use `iperf3` in both client and server modes. Firstly, we install this tool and check its version:

```bash
mpirun -np 3 --hostfile cluster_hosts iperf3 --version
```

Afterwards, four tests are performed, where a server is run on one node and a client on another node:

	1.	Master (server) ↔ Node04 (client)
	2.	Master (client) ↔ Node04 (server)
	3.	Node04 (server) ↔ Node02 (client)
	4.	Node04 (client) ↔ Node02 (server)

Each of these tests followed the `iperf3` usage pattern: 
```bash
# On server
iperf3 -s

# On client
iperf3 -c <server-hostname>
```

```bash
# Example 1: master as server, node as client
iperf3 -s  # On master
iperf3 -c master  # On node

# Example 2: node as server, master as client
iperf3 -s  # On node
iperf3 -c node  # On master
```

By repeating these tests on different node pairs, it is possible to evaluate consistency while also identifying network bottlenecks. 

== HPC workload execution

Lastly, we have to conduct a comprehensive MPI-based benchmark by executing the entire `hpcc` suite on six processes across the three containers. 
Thanks to this test it is possible to simulate a lightweight HPC cluster:
```bash
mpirun.openmpi -mca btl_tcp_if_include enp0s9 -np 6 -hostfile mpi-hostfile hpcc
```
This configuration allows for parallel execution through the specified network interface and hostfile, allowing for an end-to-end analysis of the distributed computational power in the containerised environment. 



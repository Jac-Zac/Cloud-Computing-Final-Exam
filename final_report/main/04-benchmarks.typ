#import "@preview/hei-synd-report:0.1.1": *
#import "/metadata.typ": *

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

Docker compose enabled the containerised cluster management. Thanks to a bridge network it established inter-container communication. Also, via a docker-managed volume mounted at `/shared`, shared filesystem access was enabled. 

From this starting point the following test were performed both on the VirtualBox and the Docker cluster (some test were also performed on the host machine).

== Installation

Dependencies can be installed using this script if not installed already:

```bash
./install-deps.sh
```


Folder structure to test different parts of the cluster

```bash
.
├── bin
│   ├── common.sh
│   ├── cpu-benchmark.sh
│   ├── disk-benchmark.sh
│   ├── mem-benchmark.sh
│   └── net-benchmark.sh
├── configs
│   ├── hpccinf.txt
│   └── mpi-hostfile
├── results/
├── errors.md
├── install-deps.sh
├── README.md
└── run-all.sh
```

== CPU benchmarking

=== High-Performance Linpack (HPL)
The HPL benchmark is part of the `hpcc` package, its execution aims at assessing the floating-point computation performance across the different cluster nodes. 

Firstly, we have to verify that all nodes are updated and that `hpcc` is installed. This can be done with the following command:

```bash
sudo apt update
sudo apt install hpcc
```

At this point, a hostfile that lists all node hostnames is created with the name `mpi-hostfile`. 

The benchmark is run with default parameters to check the setup integrity:

```bash
mpirun.openmpi -mca btl_tcp_if_include enp0s9 -np 6 -hostfile mpi-hostfile hpcc
```
 
Finally, the benchmark was configured for a larger problem size with the example input file (`_hpccinf.txt`) customised as follows:

```bash
1024 2048 4096 8192   Ns         (problem size)
32 64 128 256	        NBs        (block sizes)
2		                  Ps         (process grid dimension P)
3		                  Qs         (process grid dimension Q)
```

Thanks to this configuration, the work was tested on different problem sizes and spread across the cores of the different nodes.

=== Sysbench - CPU

In order to complement the HPL results, `sysbench` was used to benchmark the single-node CPU performance. Though this method lacks distributed execution support, the script was done in parallel on all nodes to showcase a more realistic cluster stress test.

We can verify the script is distributing correctly and see the version with the following commands

```bash
mpirun.openmpi -np 3 -hostfile mpi-hostfile sysbench --version
```

The next phase involves conducting comprehensive *CPU* tests. For this purpose, a custom script was developed to evaluate various components of the cluster. 
The script can be found on #link("https://github.com/Jac-Zac/Cloud-Computing-Final-Exam/blob/main/Containers/Performance_Testing/run-all.sh")[this github directory]

*It Contain tests such as the following:*

```bash
log_info "-> Sysbench (max prime = 30k)"
sysbench cpu --cpu-max-prime=30000 --threads=2 run | tee -a "$RESULTS"
```

Run the script in parallel and log the info simply by running the following command:

```bash
# Running leveraging the auxiliary script
./run_all cpu config/mpi-hostfile
```

== Memory performance

Similarly to what done for the CPU performance evaluation, memory benchmarks was also performed using `sysbench`:

```bash
log_info "-> Running sysbench memory test (500M)..."
sysbench memory --memory-block-size=1M --threads=2 --memory-total-size=500M run | tee -a "$RESULTS"

log_info "-> Running stress-ng memory test (2 workers, 1 min)..."
stress-ng --vm 2 --vm-bytes 500M --timeout 60s --metrics-brief | tee -a "$RESULTS"
```

Again by running the custom script for the memory:

```bash
./run_all mem config/mpi-hostfile
```


== Disk I/O performance

To evaluate the disk performance `IOZone` was used. With the #link("https://github.com/Jac-Zac/Cloud-Computing-Final-Exam/blob/main/Containers/Performance_Testing/bin/disk-benchmark.sh")[disk-benchmark.sh] script.

The test was performed as follows to test both the local and shared file-system:

#figure(
  sourcecode()[
    ```bash
#!/bin/bash

source "$(dirname "$0")/common.sh"

OUTPUT_FILE="${RESULTS:-disk_test_results.log}"
LOCAL_FILE="/tmp/iozone_local.tmp"
SHARED_MOUNT="/shared"
SHARED_FILE="$SHARED_MOUNT/iozone_shared.tmp"

# log_info "--- IOZone local filesystem test ---"
iozone -a -f "$LOCAL_FILE" 2>&1 | tee -a "$OUTPUT_FILE"
rm -f "$LOCAL_FILE"

if [[ -d "$SHARED_MOUNT" ]]; then
  log_info "--- IOZone shared filesystem test ---"
  iozone -a -f "$SHARED_FILE" 2>&1 | tee -a "$OUTPUT_FILE"
  rm -f "$SHARED_FILE"

else
  log_info "No shared filesystem found at $SHARED_MOUNT. Skipping shared tests."
fi
```],
  caption:"Disk performance test",
)

// not sure you want to write this:
// As expected, the NFS-based write performance was lower than local storage due to network latency.

== Network performance

To test inter-node bandwidth and latency, we use `iperf3` in both client and server modes. Firstly, we install the tool and can start the server. 

```bash
mpirun -np 3 --hostfile mpi-hostfile iperf3 --version
```

Afterwards, test were performed by having client on a node and a server on  another one.


	1.	Master (server) $<-->$ node (client)
	2.	Master (client) $<-->$ node (server)
	3.	node-01 (server) $<-->$ node-02 (client)

#infobox()[
  This test was performed using the #link("https://github.com/Jac-Zac/Cloud-Computing-Final-Exam/blob/main/Containers/Performance_Testing/bin/net-benchmark.sh")[net-benchmark.sh] script
]

To set a node as a server you can run the following command:
```bash
# On server
iperf3 -s
```

=== HPC workload execution

Additional results for the `hpcc` test performed can be found on the Github repository with relative plots inside #link("https://github.com/Jac-Zac/Cloud-Computing-Final-Exam/tree/main/benchmark_plot/plots/hpcc")[this directory]

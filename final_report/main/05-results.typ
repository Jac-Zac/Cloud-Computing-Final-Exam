#import "@preview/hei-synd-report:0.1.1": *
#import "/metadata.typ": *

= Results

== HPL test Results

#figure(
  image("/resources/img/hpcc/hpl_scaling.png"),
  caption: "HPL Performance Scaling Comparison"
)

As shown in the scaling results across different problem sizes, the performance of virtual machines and containers is relatively similar. We observe an initial increase in Tflops starting from a problem size of `1024`, which is likely too small to fully stress the processor. After this, performance plateaus, but containers still demonstrate slightly better performance overall.

#warningbox()[
This outcome is expected, as both containers and VMs involve some degree of hardware virtualization-especially on macOS, where Docker containers run inside a lightweight VM. 
Therefore, the performance gap between the two is not very large.
]

== CPU sysbench

In the following section we can see the results from sysbench.

#figure(
  image("/resources/img/cpu/events_per_sec_comparison.png"),
  caption: "CPU Performance Comparison Using Sysbench"
),

#figure(
table(
  columns: 3,
  stroke: (x: none),
  row-gutter: (3pt, auto),
  table.header[][Event per second][Configuration],
  [Host 2 CPU], [34756540], [standalone],
  [VMs 2 CPU], [2626.585], [distributed],
  [Containers 2 CPU], [2782.27], [distributed],
  ),
  caption: [Sysbench event per second comparison comparison]
),

Indeed, the number of events per second is comparable between containers and virtual machines, with containers showing a slight advantage.
The test was also conducted on the host machine, but since it was not performed in a distributed setup, its results were not directly compared with the others. As expected though, the host machine’s performance is significantly higher than both containers and virtual machines.

== Memory test results

#figure(
  image("/resources/img/memory/mem_mb_sec_comparison.png"),
  caption: "Memory Performance Comparison Using Sysbench"
),

#figure(
table(
  columns: 3,
  stroke: (x: none),
  row-gutter: (3pt, auto),
  table.header[][Memory MB/sec][Configuration],
  [Host], [58356.68], [standalone],
  [VMs], [36494.305], [distributed],
  [Containers], [40020.865], [distributed],
  ),
  caption: [Sysbench Memory Throughput Comparison]
),

The memory throughput results show that containers slightly outperform virtual machines in a distributed setup. 
Both virtualization approaches, however, deliver lower memory bandwidth compared to the host machine running standalone. 
This is expected due to the overhead introduced by virtualization layers. The host system achieves the highest memory throughput, indicating more direct and efficient access to physical memory resources.


== Disk I/O test results 

#grid(
  columns: 2,
  rows: 2,
  gutter: 5pt,
  figure(image("/resources/img/disk/iozone_local_vs_shared_bar_biggest.png"), caption: "Average Iozone Throughput"),
  figure(image("/resources/img/disk/iozone_vm_vs_container_biggest.png"), caption: "Biggest Iozone Throughput") 
),

=== Disk Write Performance: Containers vs. VMs with Shared Storage

We compared disk write performance between containers and virtual machines (VMs) under two scenarios: local storage and shared storage. In our setup, VMs use NFS for sharing folders on Linux, while containers use a Docker named volume (`hpc-shared`), which is managed by Docker and typically mapped directly.

*Key observations:*
- _Write performance:_ Containers consistently outperform VMs on shared storage writes. This is because Docker volumes avoid the overhead of network-based protocols like NFS, which require extra synchronization and introduce latency, especially for VMs.
- _Read performance:_ Read speeds are similar between containers and VMs, regardless of the storage configuration. This is mainly because reads do not require the same level of synchronization or network communication as writes. Data can be fetched directly from the underlying storage, so the network stack (such as Ethernet or NFS) does not become a bottleneck for reads.

#warningbox()[
_macOS note:_ On macOS, Docker containers themselves run inside a lightweight VM. This means container disk I/O performance is inherently similar to that of VMs, especially for read operations.
]

Docker containers with named volumes offer vastly superior shared storage performance compared to VMs using NFS. The main bottleneck for VMs is the NFS protocol overhead, while Docker volumes benefit from direct host filesystem access. This makes containers a more efficient choice for I/O-intensive workloads requiring shared storage.

#figure( image("/resources/img/disk/master_Random_Write_kB_s_4way.png", width: 80%),
  caption: "Random Write Performance Vms vs Containers 3D")

The figure above compares random write throughput for virtual machines (VMs) and containers, both with local and shared storage, across a range of file and record sizes.

We observe that **containers consistently deliver higher and more stable random write performance than VMs**, regardless of whether local or shared storage is used. This stability is particularly noticeable across varying file sizes, where containers exhibit less fluctuation in throughput.

#infobox()[
  For workloads sensitive to random write performance, containers provide a clear advantage over VMs, both in terms of absolute throughput and consistency across different I/O patterns. 
]

== Network test results 

#grid(
  columns: 2,
  rows: 2,
  gutter: 5pt,
  figure(image("/resources/img/network/avg_bw_high.png"), caption: "Average BW High"),
  figure(image("/resources/img/network/avg_bw_low.png"), caption: "Average BW Low"),
  figure(image("/resources/img/network/bw_ts_high.png"), caption: "BW TS High"),
  figure(image("/resources/img/network/bw_ts_low.png"), caption: "BW TS Low"),
),

#figure(
table(
  columns: 3,
  stroke: (x: none),
  row-gutter: (5pt, auto),
  table.header[][Avg Bandwidth (Gbits/sec)][Avg Latency (ms)],
  [node_master (container)], [127.218750], [0.11300],
  [node_node (container)], [125.687500], [0.12388],
  [master_node (container)], [126.031250], [0.11340],
  [node_master (vm)], [3.032188], [0.26070],
  [node_node (vm)], [2.909687], [0.32860],
  [master_node (vm)], [2.935313], [0.30760],
  ),
  caption: [Network Bandwidth and Latency Comparison]
),

The table compares average network bandwidth (in Gbits/sec) and latency (in ms) for communication between different host roles-node_master, node_node, and master_node-across two environments: containers and virtual machines (VMs).

=== Two Distinct Performance Groups

- _High Bandwidth (~125-127 Gbits/sec) with Low Latency (~0.11-0.12 ms):_
  Observed in all container-to-container communication pairs (node_master, node_node, master_node).  
- _Low Bandwidth (~2.9-3.0 Gbits/sec) with Higher Latency (~0.26-0.33 ms):_
  Observed in all VM-to-VM communication pairs.

This clear division aligns with the fundamental differences between containers and VMs. Containers share the host OS kernel and communicate via virtual Ethernet interfaces entirely in memory, avoiding physical network interfaces. This results in very high throughput and low latency. Indeed this result is actually very similar to what was happening when making to processes communicate on the host with the same test.

=== Differences Among Node Pairs

All node pairs share the virtualization overhead inherent to VM networking.
Differences among `node_master`, `node_node`, and `master_node` pairs might arise mainly from the master node’s role in hostname/IP management, which can optimize routing and reduce latency/bandwidth penalties for communications involving the master.

#warningbox()[
  *Warning:* Be very careful when performing tests like this. If you run `iperf` to test the master node from another node, it might resolve to `localhost` instead of the actual remote address. This can result in artificially high performance measurements that are not realistic.
]

#infobox()[
  The issue happens because the hostname _(e.g., "master")_ resolves to a loopback IP (127.0.x.x) inside the VM. As a result, iperf3 sends traffic over the VM’s loopback interface instead of the real virtual network interface. This causes the test to measure in-memory data copying rather than actual network throughput, leading to unrealistically high speeds. To fix this, use the VM’s real IP address and ensure the hostname resolves correctly, or explicitly bind iperf3 to the proper interface.
  So instead of using master (the hostname) use the actaul IP address of the master node to test performances from a worker node.
]

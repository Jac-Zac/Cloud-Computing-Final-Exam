#import "@preview/hei-synd-report:0.1.1": *
#import "/metadata.typ": *
#pagebreak()

= Results

== HPL test Results

#figure(
  image("/resources/img/hpcc/hpl_scaling.png"),
  caption: "HPL Performance Scaling Comparison"
)

As shown in the scaling results across different problem sizes, the performance of virtual machines and containers is relatively similar. We observe an initial increase in Tflops starting from a problem size of `1024`, which is likely too small to fully stress the processor. Following this, performance plateaus, but containers still demonstrate slightly better performance overall. This outcome is expected, as containers also require some hardware virtualization, so the performance gap between the two is not very large.

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

From what we can see the disk performance is as expected better in read compared to write. Espcially we can notice that in all read related task the Virtual machine suffer much more (Idk why explain it ??) Especially when the filesystem is shared it has a big impact, on the other hand reading from a shared filesystem dones't have much of an inpact. I belive hte slowdown in the write is due to the necesssary sincronization. On the other hand the containers do not really suffer much from this problem and don't have a big difference beteween shared or not and I belive this is do to how the sharing of the folder is implemented in the container which I gthink that instead of going through the netwroks is simly mapped there or something.
Morover we notice quite simlar perfrormance between virtual machiens and containers in read which is not suprising considienrg that containers on macos as previsouly state also run on a virtual machiene.,

  // figure(image("/resources/img/disk/master_node_comparison_avg.png"), caption: "BW TS High"),
//

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

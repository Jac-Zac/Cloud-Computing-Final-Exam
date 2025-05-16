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


== Network test results 

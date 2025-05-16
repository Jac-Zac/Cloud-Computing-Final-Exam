#import "@preview/hei-synd-report:0.1.1": *
#import "/metadata.typ": *

= Conclusions

In conclusion, HPL, sysbench, IOZone and iperf3 tests confirmed that containerised environment is superior compared to the VirtualBox virtual machine cluster in CPU, memory, disk I/O and network performance. 
Overall, containers showed near-native performance with less overhead, while VMs, due to their heavier virtualisation stack, exhibited performance penalties. 
These results align with the expectations that containers are more lightweight and efficient.
However, it is important to note that this project was done on a macOS system, which runs containers inside a virtualised Linux environment, introducing an additional layer of abstraction.
Thus, while containers remain superior in performance and scalability compared to VMs, the overall efficiency is not as high as it would be on native Linux host. 
Nevertheless, for HPC-like workloads that require rapid scaling and low latency inter-node communication, containers are still a better solution.
Although virtual machines are still valuable in scenarios that require strict isolation or compatibility, for most cloud-based high-performance computing workloads, a containerised solution is more advantageous.

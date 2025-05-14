#import "@preview/hei-synd-report:0.1.1": *
#import "/metadata.typ": *
#pagebreak()

= Introduction
== Objective

This report aims to evaluate and compare the performance of virtual machines (VMs) and containers in a controlled environment. Specifically, we use VirtualBox @virtualbox to deploy VMs and Docker @docker to run containers, both operating Ubuntu Server @ubuntu-server.

The experiment is structured into two phases: first, setting up a cluster of VMs and a parallel cluster of containers with equivalent resource constraints; second, executing a series of benchmarks to measure and analyze their performance.

== Benchmark Overview

The following tools and methods were used to assess different performance dimensions:

- *CPU & Memory*:
  - High-Performance Linpack (HPL) and the HPC Challenge (HPCC) suite
  - `sysbench` and `stress-ng` for general system load testing
- *Disk I/O*:
  - `IOZone` and `dd` for local disk performance
  - Optional: testing on NFS-mounted volumes
- *Network*:
  - `iperf3` for measuring throughput and latency between nodes


#infobox()[
*Note*: The term “CPU” refers to the physical processor or logical unit on the host machine. The term “cpu” (lowercase) refers to a single thread allocated to a VM or container. For example, a "VM with 4 cpus" on a host with an 8-core/16-thread CPU is assigned 4 threads from the available pool.
]

== Scope

This report focuses on:
- Documenting the setup process for both virtualized and containerized clusters
- Presenting benchmark results for each test case
- Analyzing and comparing the outcomes across environments

The full set of benchmark data and scripts used in this analysis is available on #link("https://github.com/Jac-Zac/Cloud-Computing-Final-Exam")[GitHub].

== Future Improvements

// TODO: Add academic references and formal citations for benchmarking tools used.


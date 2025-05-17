# Sysbench comparisons

## HOST

```bash
stress-ng: info:  [27983] setting to a 1 min run per stressor
stress-ng: info:  [27983] dispatching hogs: 2 cpu
stress-ng: metrc: [27983] stressor       bogo ops real time  usr time  sys time   bogo ops/s     bogo ops/s
stress-ng: metrc: [27983]                           (secs)    (secs)    (secs)   (real time) (usr+sys time)
stress-ng: metrc: [27983] cpu              316398     60.00    119.79      0.20      5273.21        2636.90
stress-ng: info:  [27983] skipped: 0
stress-ng: info:  [27983] passed: 2: cpu (2)
stress-ng: info:  [27983] failed: 0
stress-ng: info:  [27983] metrics untrustworthy: 0
stress-ng: info:  [27983] successful run completed in 1 min
```

## VMS

```bash
stress-ng: metrc: [1404] stressor       bogo ops real time  usr time  sys time   bogo ops/s     bogo ops/s
stress-ng: metrc: [1404]                           (secs)    (secs)    (secs)   (real time) (usr+sys time)
stress-ng: metrc: [1404] cpu               28202     60.01     60.00      0.00       469.95         470.02
stress-ng: info:  [1404] skipped: 0
stress-ng: info:  [1404] passed: 2: cpu (2)
stress-ng: info:  [1404] failed: 0
stress-ng: info:  [1404] metrics untrustworthy: 0
stress-ng: info:  [1404] successful run completed in 1 min, 0.02 secs
stress-ng: metrc: [1406] stressor       bogo ops real time  usr time  sys time   bogo ops/s     bogo ops/s
stress-ng: metrc: [1406]                           (secs)    (secs)    (secs)   (real time) (usr+sys time)
stress-ng: metrc: [1406] cpu               28264     60.01     59.88      0.01       470.97         471.99
stress-ng: info:  [1406] skipped: 0
stress-ng: info:  [1406] passed: 2: cpu (2)
stress-ng: info:  [1406] failed: 0
stress-ng: info:  [1406] metrics untrustworthy: 0
stress-ng: info:  [1406] successful run completed in 1 min, 0.03 secs
```

## CONTAINERS

```bash
stress-ng: info:  [133] successful run completed in 60.04s (1 min, 0.04 secs)
stress-ng: info:  [133] stressor       bogo ops real time  usr time  sys time   bogo ops/s     bogo ops/s
stress-ng: info:  [133]                           (secs)    (secs)    (secs)   (real time) (usr+sys time)
stress-ng: info:  [133] cpu               33398     60.02     59.97      0.00       556.44         556.91
stress-ng: info:  [175] successful run completed in 60.04s (1 min, 0.04 secs)
```

### What does that mean ?

- **bogo ops:** The number of "bogus operations" performed. These are synthetic operations that simulate CPU work but aren't tied to real-world units.
- **real time:** Total wall-clock time elapsed (around 60 seconds)
- **usr time:** Time spent in user space (i.e., running stress-ng code)
- **sys time:** Time spent in kernel/system space (usually low for CPU tests)
- **bogo ops/s:** _(real) bogo ops / real time — raw_ throughput
- **bogo ops/s:** _(usr+sys) bogo ops / (usr time + sys time)_ —> _"efficiency" of ops per second of actual CPU time_

I thus conclude that probably there is a normal overhead also comparing the performance is not really fair on 2 threads versus the idling system but perhaps still the other benchmark was doing a task which was too simple and also bosted the cors ?

### HOST with three processes in parallel

```bash
stress-ng: info:  [33479] dispatching hogs: 2 cpu
stress-ng: metrc: [33480] stressor       bogo ops real time  usr time  sys time   bogo ops/s     bogo ops/s
stress-ng: metrc: [33480]                           (secs)    (secs)    (secs)   (real time) (usr+sys time)
stress-ng: metrc: [33480] cpu              287899     60.00    119.92      0.07      4798.19        2399.25
stress-ng: info:  [33480] skipped: 0
stress-ng: info:  [33480] passed: 2: cpu (2)
stress-ng: info:  [33480] failed: 0
stress-ng: info:  [33480] metrics untrustworthy: 0
```

## Addiotnal tests

I tried to disassemble the binaries:

```bash
objdump -d /usr/bin/stress-ng > stress-ng.asm
```

But still found mentions of instructions such as `fadd`

**Probably the benchmark was also boosting the cpu to higher level to what the Virtual machiens allow and thus being such a short and easy benchmark I got unreliable results**

This can happen because the physical machine can boost its CPU performance dynamically, while the virtual machine may not have access to the same CPU boosting features or hardware acceleration.

In contrast, virtualization on Apple silicon generally provides near-native CPU core performance for many workloads, but some hardware features or co-processors (like the AMX matrix co-processor) used by certain optimized libraries are not available inside VMs. This can cause some specialized tasks to run significantly slower in virtualized environments. Moreover, the VM environment may impose limits on CPU frequency scaling or power management, preventing the CPU from boosting as aggressively as on the host machine.

### Interesting case study:

(Surmising CPU results)[https://eclecticlight.co/2024/01/22/why-does-virtualisation-run-some-code-far-slower-on-apple-silicon/]

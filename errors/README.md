### Setting up error

I had an issuee with dnsmasq last line then it was fixed

### I had an issue with containers not having resource restricitons

...

### Performance comparisons:

> Net

`````
Those container numbers actually make sense once you realize where the traffic is flowing:

  Container‐to‐container is purely in‐kernel memory copy
  When both endpoints live in Docker on the same host, traffic never hits a physical NIC—it goes over a pair of virtual Ethernet interfaces (veth) and is shuttled entirely in RAM by the Linux network stack. You’re essentially measuring the speed of memory-to-memory copies inside the kernel, which can easily exceed 100 Gbit/sec on a modern box (especially if you’ve got a fast CPU, plenty of RAM bandwidth, and you’re not hitting any real I/O). So seeing ~125–130 Gbit/sec there is entirely plausible.````
`````

```
VM-to-VM goes through virtualization layers
By contrast, two VMs—even on the same host—will typically talk over a virtualized switch (e.g. VirtualBox’s host-only or bridged adapter). That path involves more overhead (emulated NIC, packet copies between guest/host, context switches), so you end up closer to the physical NIC’s speed or the hypervisor’s virtual-switch limit. Hitting ~2.8–3.2 Gbit/sec there is exactly what you’d expect if your host’s real Ethernet port tops out around 1–10 Gbit (and you’re multiplexing through that), or if the hypervisor limits each guest to a few gigabits.
```

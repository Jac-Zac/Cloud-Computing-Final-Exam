### Setting up error

I had an issue with dnsmasq last line then it was fixed

### I had an issue with containers not having resource restrictions

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

Note that the output of iozone at least on the containers says this:

```bash
Timer resolution is poor. Some small transfers may have
reported inaccurate results. Sizes 64 kBytes and below.
root@986c6a33ce28:/shared/Performance_Testing/bin# ls -la
```

---

### Other error

What you’re actually seeing in that last “node→master (vm)” run isn’t the physical or virtual-bridged link at all, but the loopback/host path inside your VM—so it ends up just doing an in-kernel memory copy again.

If you look at the line:

```
Connecting to host master, port 5201
[ 5] local 127.0.0.1 port 48486 connected to 127.0.1.1 port 5201
```

…you’ll notice that master is resolving to a 127.0.x.x address inside the guest. That means iperf3 is talking over the VM’s loopback interface (or a host-only adapter that’s really just looping back in software), not over the bridged‐or-NAT’d vNIC you thought you were measuring. Loopback traffic again lives entirely in RAM, so you get those gigantic 100+ Gbit/sec rates.
How to get a “real” VM-to-VM number

Use the VM’s actual non-loopback IP
In your examples above, when you pinged 192.168.56.x you got ~3 Gbit/sec—that’s the bridged/host-only virtual NIC speed. If you force iperf3 to connect to that address instead of master (127.0.x.x), you’ll see the ~2–3 Gbit/sec result.

Check /etc/hosts or your DNS
You probably have a line in /etc/hosts like:

```
127.0.1.1 master
```

That makes the hostname master point at loopback. Remove or override that so master resolves to e.g.

```
192.168.56.10 master
```

Explicitly bind to the desired interface
You can tell iperf3 which local address to use with -B, for example:

```bash
iperf3 -c master -B 192.168.56.11
```

That will force it onto the VM’s “real” vNIC instead of loopback.

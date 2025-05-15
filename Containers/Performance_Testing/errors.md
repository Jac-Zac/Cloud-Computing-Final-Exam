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

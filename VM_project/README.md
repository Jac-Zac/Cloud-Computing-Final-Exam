# Cloud Exam Virtual Machine Setup Guide

This guide walks through setting up a VM cluster for cloud environment testing, with one master node and multiple worker nodes.

## Table of Contents
- [Initial Template Setup](#initial-template-setup)
- [Cloning VMs](#cloning-vms)
- [Network Configuration](#network-configuration)
- [Master Node Configuration](#master-node-configuration)
- [Node Access and Management](#node-access-and-management)

## Initial Template Setup

### Create Base Template VM
1. Download and install [ARM version of Ubuntu Server](https://ubuntu.com/download/server/arm)
2. Use unattended installation with these credentials:
   - Username: `user01`
   - Password: `test`

### Configure VirtualBox Internal Network

Create a Host-Only network named "CloudBasicNet" with:
```
Mask: 255.255.255.0
Lower Bound: 192.168.56.2
Upper Bound: 192.168.56.199
```

## Cloning VMs

Clone the template VM to create your cluster:

```bash
VBoxManage clonevm "template" --name "master" --register --mode all
VBoxManage clonevm "template" --name "node-01" --register --mode all
VBoxManage clonevm "template" --name "node-02" --register --mode all
```

> **TIP**: List all your virtual machines with: `VBoxManage list vms`

## Network Configuration

### Configure Network Adapters

For each VM (master and all nodes), configure a second network adapter:

```bash
# Enable Adapter 2 and set to "Internal Network"
VBoxManage modifyvm "VM_NAME" --nic2 intnet

# Assign to "CloudBasicNet" network
VBoxManage modifyvm "VM_NAME" --intnet2 "CloudBasicNet"
```

Replace `VM_NAME` with "master", "node-01", etc. for each machine.

### Enable SSH Port Forwarding

Configure port forwarding to access VMs via SSH:

```bash
# For master node (accessible on localhost:3022)
VBoxManage modifyvm "master" --natpf1 "ssh,tcp,127.0.0.1,3022,,22"

# For worker node 1 (accessible on localhost:4022)
VBoxManage modifyvm "node-01" --natpf1 "ssh,tcp,127.0.0.1,4022,,22"

# Add similar rules for other nodes as needed
```

## Master Node Configuration

> [!TIP]
>```bash
># Start VM in headless mode
>VBoxManage startvm "VM_NAME" --type headless
># Save VM state and stop
>VBoxManage controlvm "VM_NAME" savestate
>```

### SSH Key Setup

1. Copy your SSH public key to the master node:
   ```bash
   scp -P 3022 ~/.ssh/id_ed25519.pub user01@127.0.0.1:~
   ```

2. SSH into the master node:
   ```bash
   ssh -p 3022 user01@127.0.0.1
   ```

3. Configure SSH authentication:
   ```bash
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   cat ~/id_ed25519.pub >> ~/.ssh/authorized_keys
   chmod 644 ~/.ssh/authorized_keys
   rm ~/id_ed25519.pub
   ```

### Copy Configuration Files

Transfer configuration files to the master node:
```bash
scp -P 3022 -r master_config user01@127.0.0.1:~
```

### Network Configuration

1. Apply the network configuration:
   ```bash
   sudo cp ~/master_config/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml
   sudo netplan apply
   ```

2. Set the hostname:
   ```bash
   echo "master" | sudo tee /etc/hostname > /dev/null
   ```

3. Update hosts file:
   ```bash
   sudo cp ~/master_config/hosts /etc/hosts
   ```

### DNS and DHCP Configuration

1. Install DNSmasq:
   ```bash
   sudo apt install dnsmasq -y
   ```

2. Configure DNSmasq:
   ```bash
   sudo cp ~/master_config/dnsmasq.conf /etc/dnsmasq.conf
   ```

3. Configure DNS resolution:
   ```bash
   sudo unlink /etc/resolv.conf
   sudo cp ~/master_config/resolv.conf /etc/resolv.conf
   sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.dnsmasq
   sudo systemctl restart dnsmasq systemd-resolved
   ```

4. Enable DNSmasq on startup:
   ```bash
   sudo systemctl enable dnsmasq
   ```

5. Apply changes:
   ```bash
   sudo reboot
   ```

## Node Access and Management

After reboot, access the master node:
```bash
ssh -p 3022 user01@127.0.0.1
```

From here, you can manage your cluster and configure worker nodes as needed.

---

## Terminal Commands Reference

### VM Management
- Create VM clones: `VBoxManage clonevm [SOURCE] --name [NAME] --register --mode all`
- List VMs: `VBoxManage list vms`
- Start VM: `VBoxManage startvm [NAME] --type headless`
- Save VM state: `VBoxManage controlvm [NAME] savestate`

### Network Configuration
- Port forwarding: `VBoxManage modifyvm [NAME] --natpf1 "ssh,tcp,127.0.0.1,[PORT],,22"`
- Set internal network: `VBoxManage modifyvm [NAME] --nic2 intnet --intnet2 "CloudBasicNet"`

### SSH Access
- Connect: `ssh -p [PORT] user01@127.0.0.1`
- Copy files: `scp -P [PORT] [SOURCE] user01@127.0.0.1:[DESTINATION]`

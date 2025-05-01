# Cloud Exam Virtual Machine Setup Guide

This guide walks through setting up a VM cluster for cloud environment testing, with one master node and multiple worker nodes.

## Table of Contents
- [Initial Template Setup](#initial-template-setup)
- [Cloning VMs](#cloning-vms)
- [Network Configuration](#network-configuration)
- [Master Node Configuration](#master-node-configuration)
- [Node Access and Management](#node-access-and-management)

---

# Initial Template Setup

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

> [!TIP]
> List all your virtual machines with: `VBoxManage list vms`

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

---

# Master Node Configuration

> [!TIP]
> ```bash
> # Start VM in headless mode
> VBoxManage startvm "VM_NAME" --type headless
> # Save VM state and stop
> VBoxManage controlvm "VM_NAME" savestate
> ```

### SSH Key Setup

1. Copy your SSH public key to the master node:
   ```bash
   scp -P 3022 ~/.ssh/id_ed25519.pub user01@127.0.0.1:~
   ```

2. SSH into the master node:
   ```bash
   ssh -p 3022 user01@127.0.0.1
   ```

   > [!TIP]
   > To exit an SSH session, type `exit` or press `Ctrl+D`

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

> [!TIP]
> To copy files from the VM to your host machine, reverse the source and destination:
> ```bash
> scp -P 3022 user01@127.0.0.1:~/config_file ./local_directory/

Create a key also on the master node:

```bash
ssh-keygen
```

## Network Configuration

### Base Network Setup
1. Apply the network configuration:
   ```bash
   sudo cp ~/master_config/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml
   sudo netplan apply
   ```

2. Set the hostname:
   ```bash
   echo "master" | sudo tee /etc/hostname > /dev/null
   sudo hostnamectl set-hostname master  # Ensure hostname is set immediately
   ```

   > [!TIP]
   > Verify hostname changes with: `hostname`

3. Update hosts file:
   ```bash
   sudo cp ~/master_config/hosts /etc/hosts
   ```

### DNS and DHCP Configuration

1. Install DNSmasq:
   ```bash
   sudo apt update
   sudo apt install dnsmasq -y
   ```

   > [!TIP]
   > Check installation status with: `systemctl status dnsmasq`

2. Configure DNSmasq:
   ```bash
   sudo cp ~/master_config/dnsmasq.conf /etc/dnsmasq.conf
   sudo mkdir -p /etc/dnsmasq.d  # Create directory for additional configurations
   ```

3. Configure DNS resolution:
   ```bash
   # Backup original resolv.conf
   sudo cp /etc/resolv.conf /etc/resolv.conf.backup
   
   # Remove existing symlink if present
   sudo unlink /etc/resolv.conf
   
   # Set up new configuration
   sudo cp ~/master_config/resolv.conf /etc/resolv.conf
   sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.dnsmasq
   
   # Restart relevant services
   sudo systemctl restart dnsmasq
   sudo systemctl restart systemd-resolved
   ```

   > [!TIP]
   > Test DNS resolution with: `nslookup google.com` or `ping -c 3 master`

4. Enable DNSmasq on startup:
   ```bash
   sudo systemctl enable dnsmasq
   ```

5. Apply changes:
   ```bash
   sudo reboot
   # Wait for system to reboot before proceeding to next steps
   ```

   > [!TIP]
   > After reboot, reconnect with: `ssh -p 3022 user01@127.0.0.1`

### NFS Server Setup

1. Install NFS server:
   ```bash
   sudo apt update
   sudo apt install nfs-kernel-server -y
   ```

2. Create shared directory:
   ```bash
   sudo mkdir -p /shared
   sudo chmod 777 /shared  # Set appropriate permissions
   ```

   > [!TIP]
   > For production environments, use more restrictive permissions: `sudo chmod 755 /shared`

3. Configure NFS exports:
   ```bash
   # Add export configuration without overriding existing comments
   echo '/shared/ 192.168.56.0/255.255.255.0(rw,sync,no_root_squash,no_subtree_check)' | sudo tee -a /etc/exports > /dev/null
   ```

   > [!TIP]
   > View current exports with: `cat /etc/exports`

4. Enable and restart the NFS server:
   ```bash
   sudo systemctl enable nfs-kernel-server
   sudo systemctl restart nfs-kernel-server
   ```

   > [!TIP]
   > Check NFS server status: `sudo systemctl status nfs-kernel-server`
   > Verify exports: `showmount -e localhost`

5. Create shared directories:
   ```bash
   sudo mkdir -p /shared/data /shared/home
   sudo chmod 777 /shared/data /shared/home
   ```

---

# Node configurations

Bootstrap the VM node-01 and configure the secondary network adapter with a dynamic IP

Copy the configurations:

``` bash
scp -P 3022 user01@127.0.0.1:~/node_config ./node_config 
```

To do this we will edit the netplan file:

```bash
sudo cp ~/node_config/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml
```

apply the configuration

```bash
sudo netplan apply
```

Empty the /etc/hostname file

```bash
echo "" | sudo tee /etc/hostname > /dev/null
```

Set the proper dns server (assigned with dhcp):

```bash
sudo unlink /etc/resolv.conf
sudo cp ~/node_config/resolv.conf /etc/resolv.conf
```

```bash
sudo reboot
```

### Node Access and Management

After reboot, access the master node:

```bash
ssh -p 3022 user01@127.0.0.1
```

From here, you can manage your cluster and configure worker nodes as needed.

> [!TIP]
> To access worker nodes from the master node, use: `ssh user01@node-01` or `ssh user01@node-02`

### Client-Side NFS Setup

To mount the shared filesystem on client nodes:

```bash
# Install NFS client
sudo apt install nfs-common -y

# Create mount points
sudo mkdir -p /shared/data /shared/home
```

> [!TIP]
> Check available NFS exports with: `showmount -e 192.168.56.1`

### Set up automatically mounting

Install necessary libraries

```bash
sudo apt -y install autofs
```

**Configure auto mount**

```bash
echo '/shared /etc/auto.shared' | sudo tee -a /etc/auto.master > /dev/null
echo "# create new : [mount point] [option] [location]" | sudo tee /etc/auto.mount > /dev/null
echo "data    192.168.56.1:/shared" | sudo tee -a /etc/auto.mount > /dev/null
```

Restart the service

```bash
sudo systemctl restart autofs
```

Add more configurations setups


> [!TIP]

> Verify mounts with: `df -h | grep shared` or `mount | grep nfs`

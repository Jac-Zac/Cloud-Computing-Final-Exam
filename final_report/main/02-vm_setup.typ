#import "@preview/hei-synd-report:0.1.1": *
#import "/metadata.typ": *
#pagebreak()

= Virtual Machine Cluster Setup

What follows are the steps to set up and network the virtual machines on which we will later conduct performance tests. 
For this, we setup VirtualBox. The tutorial #footnote()[https://github.com/Foundations-of-HPC/Cloud-basic-2024/blob/main/Tutorials/VirtualMachine/README.md] referenced throughout this section was instrumental in guiding the process.

This modified guide walks through setting up a VM cluster for cloud environment testing, with I used to perform the test. 

== Setting Up the Template VM

1. Create a new virtual machine in VirtualBox by clicking on _Machine > New_.
2. Enter the template as the name for the VM, select the storage directory on the host, and choose the Ubuntu 24.04.1 amd64 server ISO image.
3. Skip the unattended installation process, as it may cause issues.
4. Configure hardware, the settings used in this case are: *2GB RAM and 2 CPU* (adjust based on host capabilities).
5. Set the virtual hard disk size to 20GB.

=== Installing Ubuntu Server

After configuring the Virtual Machine, start it and follow the installation wizard.
1. Carefully select the language and keyboard layout
2. Choose the standard Ubuntu Server installation
3. Leave the network configuration at its default for now; we will adjust this later.
4. Leave the proxy address blank.
5. Select a suitable mirror address; the installer will test options.
6. For storage, use the "entire disk" option and enable _LVM group_ setup.
7. Set up the user profile (e.g., username: user01, server name: template).
8. Skip Ubuntu Pro registration.
9. Enable the OpenSSH server for remote access.
10. Skip additional suggested packages.
11. Complete the installation, then shut down the VM and remove the ISO image.

=== Configuring the Template

Firstly, start the machine created earlier and log in with the credentials `username: user01` and `password: test` which were set up previously. Then test if the network connectivity is working correctly.
Next update the software using the following command:

```bash
sudo apt update && sudo apt upgrade
```

It is important to install two additional packages, this can be done with this command:

```bash
sudo apt install net-tools gcc make
```

Finally, we have to shutdown the node with the following command: 

```bash
sudo shutdown -h now
```


=== Configure VirtualBox Internal Network

Create a Host-Only network named "CloudBasicNet" with:

```bash
Mask: 255.255.255.0
Lower Bound: 192.168.56.2
Upper Bound: 192.168.56.199
```

== Configuring the entire cluster (with automated script)

Due to many inconveniences and problems in the process of setting up the machines and for ease of use in the future, I have created a script to create the cluster.
It can be found in the git repository #footnote()[https://github.com/Jac-Zac/Cloud-Computing-Final-Exam].

The `setup_node.sh` script automates the VM setup process for both master and worker nodes. It handles VM cloning, network configuration, SSH setup, and service configuration.

=== Prerequisites

- VirtualBox installed
- A template VM named `template` already created
- *Configuration directories:*
#infobox()[
  - `master_config/` — Contains configuration files for master node
  - `node_config/` — Contains generic configuration for worker nodes
Those configuration can also be found inside the GitHub directory with all the other configurations and scripts.
]

== Basic Usage

#figure(
  sourcecode(lang: "bash")[
```bash
# Usage: ./setup_node.sh [node_name] [ssh_port] [password]
# More details are present when running ./setup_node.sh --help

# Set up master node (will use port 3022 for SSH by default)
./setup_node.sh master

# Set up worker nodes (using different SSH ports)
./setup_node.sh node-01 4022
./setup_node.sh node-02 5022
```],
  caption: "Basic usage of setup_node.sh script",
)

=== Advanced Usage

You can specify the node name, SSH port, and password:

#figure(
  sourcecode(lang: "bash")[
```bash
./setup_node.sh [node_name] [ssh_port] [password]

# Example:
./setup_node.sh node-01 4022 custom_password
```],
  caption: "Advanced usage of setup_node.sh script",
)

#ideabox()[
  Note the script has been written in parallel incrementally when setting up the cluster and then refined at the end to improve it drastically.
  It can now be easily used to completely recreate the environment from scratch which is actually what I have done in the end.
]

=== Access Pattern

- *Master Node*: Direct SSH access from your local machine
- *Worker Nodes*: SSH access only through the master node

Connect to the master node first:

```bash
ssh -i ~/.ssh/id_ed25519 -p 3022 user01@127.0.0.1
```

Then from the master, connect to worker nodes:

```bash
ssh node-0n
```

== Manual Setup of the VMs

An alternative set up is to build the cluster manually, more informations can be found on #link("https://github.com/Foundations-of-HPC/Cloud-basic-2024/tree/main/Tutorials/VirtualMachine")[this provided tutorial].
Which has been updated and now works without any changed to the DNS configuration.

#infobox()[
  Note that the following section showcases many commands that can be run through the terminal instead of interacting with the GUI. Those command are exactly what is being run under the hood in the automated script.
]

=== Cloning VMs

```bash
VBoxManage clonevm "template" --name "master" --register --mode all
VBoxManage clonevm "template" --name "node-01" --register --mode all
```

List all your virtual machines with: `VBoxManage list vms`

=== Network Configuration

==== Configure Network Adapters

```bash
VBoxManage modifyvm "VM_NAME" --nic2 intnet
VBoxManage modifyvm "VM_NAME" --intnet2 "CloudBasicNet"
```

Replace *VM_NAME* accordingly.

==== Enable SSH Port Forwarding

```bash
VBoxManage modifyvm "master" --natpf1 "ssh,tcp,127.0.0.1,3022,,22"
VBoxManage modifyvm "node-01" --natpf1 "ssh,tcp,127.0.0.1,4022,,22"
```

== Master Node Configuration

=== SSH Key Setup

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub -p 3022 user01@127.0.0.1
```

=== Copy Configuration Files

```bash
scp -P 3022 -r master_config user01@127.0.0.1:~
```

Generate SSH key:
```bash
ssh-keygen
```

=== Network Setup
This setup can be done leveraging the configuration files that are inside the master_con fig directory which we moved to the node

```bash
sudo cp ~/master_config/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml
sudo netplan apply

echo "master" | sudo tee /etc/hostname > /dev/null
sudo hostnamectl set-hostname master
sudo cp ~/master_config/hosts /etc/hosts
```

=== DNS and DHCP Setup

```bash
# Update package list and install dnsmasq
sudo apt update && sudo apt install dnsmasq -y

# Replace dnsmasq configuration with custom file
sudo cp ~/master_config/dnsmasq.conf /etc/dnsmasq.conf

# Ensure directory for additional dnsmasq configs exists
sudo mkdir -p /etc/dnsmasq.d

# Backup current resolver config and replace with custom one
sudo cp /etc/resolv.conf /etc/resolv.conf.backup
sudo unlink /etc/resolv.conf
sudo cp ~/master_config/resolv.conf /etc/resolv.conf

# Link systemd-resolved's resolv.conf for dnsmasq use
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.dnsmasq

# Restart services to apply changes
sudo systemctl restart dnsmasq
sudo systemctl restart systemd-resolved

# Enable dnsmasq to start on boot
sudo systemctl enable dnsmasq

# Reboot to finalize setup
sudo reboot
```

#warningbox()[After bootstrap may happen the dnsmasq service start before the interfaces, just restart the service (the problem can be fixed with some configuration).

```bash
sudo systemctl restart dnsmasq systemd-resolved
```

Though I have added a way to fix the problem automatically inside *fix_dnsmasq_startup.sh* script
]

=== NFS Server Setup

Setting up a shared file system is essential in our project. We can manually doing performing the following actions

```bash
sudo apt install nfs-kernel-server -y

# Create shared directory for NFS exports
sudo mkdir -p /shared

# Set permissions to allow full access to all users
sudo chmod 777 /shared

# Add NFS export entry for the 192.168.56.0/24 subnet with specified options
echo '/shared/ 192.168.56.0/255.255.255.0(rw,sync,no_root_squash,no_subtree_check)' | sudo tee -a /etc/exports

# Enable NFS server to start on boot and restart NFS server to apply export changes
sudo systemctl enable nfs-kernel-server
sudo systemctl restart nfs-kernel-server

# Create additional subdirectories inside the shared folder
sudo mkdir -p /shared/data /shared/home /shared/ssh-keys

# Set full access permissions on the new subdirectories
sudo chmod 777 /shared/data /shared/home /shared/ssh-keys
```

Note that we write `192.168.56.0/255.255.255.0` to specifies the allowed client network (all hosts in the 192.168.56.x subnet).

(rw,sync,no_root_squash,no_subtree_check) are options controlling how clients can access the share:

- rw: clients have read and write permissions.
- sync: writes to the shared directory are committed synchronously for data integrity.
- no_root_squash: remote root users retain root privileges on the share (not mapped to a less privileged user).
- no_subtree_check: disables subtree checking to improve reliability when exporting directories that may be moved or renamed.

This entry allows all machines in the specified subnet to mount and fully access the `/shared/` directory with the defined options.

== Worker Node Configuration

We can now startup the machine copy the user configuration inside by coping the `node_config` directory and then ssh into the node to configure it

=== Initial Setup

```bash
scp -P 4022 user01@127.0.0.1:~/node_config ./node_config
ssh user01@node-01
```

=== Network Setup

Configure the network applying the configurations present on github.

```bash
sudo cp ~/node_config/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml
sudo netplan apply

echo "" | sudo tee /etc/hostname > /dev/null
sudo unlink /etc/resolv.conf
sudo cp ~/node_config/resolv.conf /etc/resolv.conf
sudo reboot
```

=== NFS Client Setup

Setting up a NFS client to automatically do the mounting of the shared file system at startup

```bash
sudo apt install nfs-common -y
sudo mkdir -p /shared/data /shared/home
```

==== AutoFS Setup

To mount it directly ot the shared directory we can configure it as followed. Which is also what was done in the automatic script.

```bash
sudo apt -y install autofs
echo '/-      /etc/auto.shared' | sudo tee -a /etc/auto.master > /dev/null
echo "/shared    master:/shared" | sudo tee -a /etc/auto.mount > /dev/null
sudo systemctl enable autofs
sudo systemctl restart autofs
```

=== Testing & Verification

To conclude the setup we can test the shared file system and check that we can correctly ping nodes by host name

```bash
touch /shared/data/test-from-node-01
ls -la /shared/data/

ping -c 3 master
```

== Node Management

We can finalize the setup by creating a key on master and coping it to the shared file-system and then from the node directly add the key to the authorized keys

=== Node Status Script

Finally we can create/use the following script to check what nodes are running.

#figure(
  sourcecode(lang: "bash")[
    ```bash
    #!/bin/bash
    n=${1:-9}
    nodes=(master)
    for i in $(seq 1 "$n"); do
      num=$(printf "%02d" "$i")
      nodes+=("node-$num")
    done

    for node in "${nodes[@]}"; do
      echo -n "$node: "
      ping -c 1 -W 1 "$node" >/dev/null && echo "UP" || echo "DOWN"
    done
    ```
  ],
  caption: "Script check_node.sh: to get the machines that are up",
)

#ideabox()[Save scripts in `/shared/scripts/` for shared access]

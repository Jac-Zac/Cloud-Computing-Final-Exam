# Cloud exam Virtual Machine (part 1)

## Create a Template 
> [!TODO]
> Explain how to do this from the terminal

- Install [arm version of ubuntu server](https://ubuntu.com/download/server/arm)
- Unattended Install:

  - username: `user01`
  - password: `test`

### Configure the VBOx internal network.

Created an Host Only network, named CloudBasicNet

```
Mask: 255.255.255.0
Lower Bound: 192.168.56.2
Upper Bound: 192.168.56.199
```


#### Clone to create your other nodes:

```bash
VBoxManage clonevm "template" --name "master" --register --mode all
VBoxManage clonevm "template" --name "node-01" --register --mode all
VBoxManage clonevm "template" --name "node-02" --register --mode all
```

---

### Configure the nodes
Add a new network adapter on each machine: `internal network` naming it: "CloudBasicNet".

### Enable port forwarding
> To connect to the virtual machines we can enable port forwarding

### Configuring Network Virtual Box

##### Using a rule like this:

- Name -> ssh
- Protocol -> TCP
- HostIP -> 127.0.0.1
- Host Port -> some_port_number
- Guest Port -> 22

An example of how to do it from the terminal could be this:

_This example configures it both for the master and for the node-01._

> [!TIP]
> Your virtual machines names can be seen with: ```VBoxManage list vms```

```bash
VBoxManage modifyvm "master" --natpf1 "ssh,tcp,127.0.0.1,3022,,22"
VBoxManage modifyvm "node-01" --natpf1 "ssh,tcp,127.0.0.1,4022,,22"
```

#### Configuring Network Adapter

1. Enables Adapter 2 and sets its mode to "Internal Network".a

  ```bash
  VBoxManage modifyvm "master" --nic2 intnet
  ````

2. Assigns the network name _"CloudBasicNet"_ to Adapter 2.

  ```bash
  VBoxManage modifyvm "master" --intnet2 "CloudBasicNet"
  ```

Add a new network adapter on each machine: enable "Adapter 2

**Similarly do this for each node-n**

## Master node configuration

> [!TIP]
> You can start the VM in headless mode from the terminal:
> ```bash
>  VBoxManage startvm "VM_name" --type headless
> You can also stop a machine and save the state of it with this command
>  ```
> ```bash
>  VBoxManage controlvm "VM_name" savestate
>  ```

### Initial setup

After you have created the node and a key you can copy the key to the master node. You can start the machine and copy things into it

```bash
 scp -P 3022  ~/.ssh/id_ed25519.pub user01@127.0.0.1:~ 
```

You can ssh into the machine for some additional configuration

```bash
ssh -p 3022 user01@127.0.0.1
```

And set up your ssh key to work correctly:

```bash
mkdir ~/.ssh
chmod 700 ~/.ssh
cat ~/id_ed25519.pub >> ~/.ssh/authorized_keys
chmod 644 ~/.ssh/authorized_keys
rm ~/id_ed25519.pub # Delete usless key in the home directory
```

Moreover you can copy some other configuration files with the following command:

```bash
scp -P 3022 -r master_config user01@127.0.0.1:~
```

### Configure the network


ssh into the machine and start working from it

```bash
ssh -p 3022 user01@127.0.0.1
```

Create and apply the custom configuration for the master node:

```bash
sudo cp ~/master_config/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml
sudo netplan apply
```

Change the hostname to master:

```bash
# Write to etc/hostname and pass the output to /dev/null to avoid printing to the shell
echo "master" | sudo tee /etc/hostname > /dev/null
```

Change the host file:

```bash
sudo cp ~/master_config/hosts /etc/host
```

Install a dnsmasq server to dynamically assign the IP and hostname to the other nodes on the internal interface and create a cluster.

```bash
sudo apt install dnsmasq -y
```

Configure Dnsmasq with the provided configuration. 

```bash
sudo cp ~/master_config/dnsmasq.conf /etc/dnsmasq.conf
```

Configure the resolve:

```bash
sudo unlink /etc/resolv.conf
sudo cp ~/master_config/resolv.conf /etc/resolv.conf
sudo ln -s  /run/systemd/resolve/resolv.conf /etc/resolv.dnsmasq
sudo systemctl restart dnsmasq systemd-resolved
```

```bash
sudo systemctl enable dnsmasq
```

**Reboot the machine**

```bash
sudo reboot
```

SSH into it again:



![usful idea](../assets/notes.png)

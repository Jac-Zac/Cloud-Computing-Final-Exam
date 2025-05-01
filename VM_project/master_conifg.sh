#!/bin/bash
# Master Node Setup Script
# This script automates the setup of the master node for cloud exam environment
# Usage: ./setup_master.sh [password]

set -e  # Exit on error

# Default values
DEFAULT_PASSWORD="test"
VM_NAME="master"
USERNAME="user01"
SSH_PORT=3022
HOST_IP="127.0.0.1"
NETWORK_NAME="CloudBasicNet"

# Function to display script usage
show_usage() {
  echo "Usage: $0 [password]"
  echo ""
  echo "Arguments:"
  echo "  password - VM user password (default: $DEFAULT_PASSWORD)"
  echo ""
  echo "Example:"
  echo "  $0 mypassword"
}

# Function to check if the master VM exists
master_exists() {
  VBoxManage list vms | grep -q "\"$VM_NAME\""
  return $?
}

# Function to clone VM from template
clone_master() {
  local template_name="template"
  
  if ! VBoxManage list vms | grep -q "\"$template_name\""; then
    echo "Error: Template VM '$template_name' does not exist!"
    echo "Please create a template VM first."
    exit 1
  fi
  
  if master_exists; then
    echo "VM '$VM_NAME' already exists. Skipping clone operation."
  else
    echo "Cloning VM '$template_name' to '$VM_NAME'..."
    VBoxManage clonevm "$template_name" --name "$VM_NAME" --register --mode all
    echo "VM cloned successfully."
  fi
}

# Function to configure network settings
configure_network() {
  echo "Configuring network for master node with SSH port $SSH_PORT..."
  
  # Configure network adapter for internal network
  VBoxManage modifyvm "$VM_NAME" --nic2 intnet
  VBoxManage modifyvm "$VM_NAME" --intnet2 "$NETWORK_NAME"
  
  # Configure port forwarding for SSH
  # First remove existing rule if it exists
  VBoxManage modifyvm "$VM_NAME" --natpf1 delete "ssh" 2>/dev/null || true
  VBoxManage modifyvm "$VM_NAME" --natpf1 "ssh,tcp,$HOST_IP,$SSH_PORT,,22"
  
  echo "Network configuration completed."
}

# Function to start VM
start_master() {
  if VBoxManage showvminfo "$VM_NAME" | grep -q "running"; then
    echo "Master VM is already running."
  else
    echo "Starting master VM in headless mode..."
    VBoxManage startvm "$VM_NAME" --type headless
    
    # Wait for VM to boot
    echo "Waiting for VM to boot (60 seconds)..."
    sleep 60
  fi
}

# Function to setup SSH key
setup_ssh_key() {
  echo "Setting up SSH key authentication..."
  
  # Generate SSH key if it doesn't exist
  if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
    echo "SSH key generated."
  fi
  
  # Copy SSH key to VM
  sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -P "$SSH_PORT" ~/.ssh/id_ed25519.pub "$USERNAME@$HOST_IP:~/"
  
  # Configure SSH key on VM
  sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "$USERNAME@$HOST_IP" "
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    cat ~/id_ed25519.pub >> ~/.ssh/authorized_keys
    chmod 644 ~/.ssh/authorized_keys
    rm ~/id_ed25519.pub
  "
  
  echo "SSH key setup completed."
}

# Function to copy configuration files
copy_config_files() {
  echo "Copying configuration files to master VM..."
  
  # Create a temporary directory for the master configuration
  TEMP_DIR=$(mktemp -d)
  
  # Copy the existing configuration files to the temp directory
  cp ./master_50-cloud-init.yaml "$TEMP_DIR/50-cloud-init.yaml"
  cp ./master_dnsmasq.conf "$TEMP_DIR/dnsmasq.conf"
  cp ./master_resolv.conf "$TEMP_DIR/resolv.conf"
  cp ./master_hosts "$TEMP_DIR/hosts"
  
  # Copy the temporary directory to the VM
  scp -o StrictHostKeyChecking=no -P "$SSH_PORT" -r "$TEMP_DIR/" "$USERNAME@$HOST_IP:~/master_config"
  
  # Clean up
  rm -rf "$TEMP_DIR"
  
  echo "Configuration files copied."
}

# Function to configure master VM
configure_master() {
  echo "Configuring master node..."
  
  # Run configuration commands on VM
  ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "$USERNAME@$HOST_IP" "
    # Apply network configuration
    sudo cp ~/master_config/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml
    sudo netplan apply
    
    # Set hostname
    echo '$VM_NAME' | sudo tee /etc/hostname > /dev/null
    
    # Update hosts file
    sudo cp ~/master_config/hosts /etc/hosts
    
    # Install and configure dnsmasq
    sudo apt update
    sudo apt install -y dnsmasq
    
    # Configure dnsmasq
    sudo cp ~/master_config/dnsmasq.conf /etc/dnsmasq.conf
    
    # Configure DNS resolution
    sudo unlink /etc/resolv.conf 2>/dev/null || true
    sudo cp ~/master_config/resolv.conf /etc/resolv.conf
    sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.dnsmasq
    sudo systemctl restart dnsmasq systemd-resolved
    sudo systemctl enable dnsmasq
    
    echo 'Master node configuration completed.'
  "
  
  echo "Master node configured successfully."
}

# Function to reboot master VM
reboot_master() {
  echo "Rebooting master node..."
  
  ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "$USERNAME@$HOST_IP" "sudo reboot"
  
  echo "Master node is rebooting. Wait a minute before connecting again."
  echo "You can connect using: ssh -p $SSH_PORT $USERNAME@$HOST_IP"
}

# Main execution starts here
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  show_usage
  exit 0
fi

# Get password from argument or use default
PASSWORD=${1:-$DEFAULT_PASSWORD}

echo "=========================================================="
echo "Master Node Setup"
echo "=========================================================="
echo "VM Name: $VM_NAME"
echo "Username: $USERNAME"
echo "SSH Port: $SSH_PORT"
echo "=========================================================="

# Check for required tools
for cmd in VBoxManage ssh scp sshpass; do
  if ! command -v $cmd &> /dev/null; then
    echo "Error: '$cmd' is required but not installed."
    case $cmd in
      VBoxManage) echo "Please install VirtualBox." ;;
      sshpass) echo "Please install sshpass: sudo apt install sshpass" ;;
      ssh|scp) echo "Please install OpenSSH client: sudo apt install openssh-client" ;;
    esac
    exit 1
  fi
done

# Check for required configuration files
for file in 50-cloud-init.yaml dnsmasq.conf hosts resolv.conf; do
  if [ ! -f "./$file" ]; then
    echo "Error: Required configuration file './$file' not found!"
    echo "Please ensure all configuration files are in the current directory."
    exit 1
  fi
done

# Main workflow
echo "Starting master node setup process..."
clone_master
configure_network
start_master
setup_ssh_key
copy_config_files
configure_master
reboot_master

echo "=========================================================="
echo "Master node setup completed successfully!"
echo "You can connect to it using:"
echo "ssh -p $SSH_PORT $USERNAME@$HOST_IP"
echo "=========================================================="

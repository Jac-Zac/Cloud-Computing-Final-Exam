#!/bin/bash
# Master Node Setup Script
# Usage: ./setup_master.sh [password]
# Improved version with better error handling, connection verification, and security

set -e

# Defaults
DEFAULT_PASSWORD="test"
VM_NAME="master"
USERNAME="user01"
SSH_PORT=3022
HOST_IP="127.0.0.1"
NETWORK_NAME="CloudBasicNet"
MAX_RETRIES=10
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5"

# Text formatting
BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

# Log functions
log_info() { echo -e "${GREEN}[INFO]${RESET} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${RESET} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${RESET} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${RESET} $1"; }

# Show usage
show_usage() {
  cat <<EOF
Usage: $0 [password]

Arguments:
  password  VM user password (default: $DEFAULT_PASSWORD)

Example:
  $0 mypassword
EOF
}

# Check if VM exists
vm_exists() {
  VBoxManage list vms | grep -q "\"$1\""
  return $?
}

# Check if VM is running
vm_running() {
  VBoxManage showvminfo "$1" 2>/dev/null | grep -q '^State:.*running'
  return $?
}

# Wait for SSH to become available
wait_for_ssh() {
  local host="$1"
  local port="$2"
  local retries=0
  local max_retries="${MAX_RETRIES:-10}"
  local sleep_time=5

  log_info "Waiting for SSH to become available..."
  while ! ssh $SSH_OPTS -p "$port" "${USERNAME}@${host}" "exit" &>/dev/null; do
    retries=$((retries + 1))
    if [ "$retries" -ge "$max_retries" ]; then
      log_error "Could not connect to SSH after $max_retries attempts"
      return 1
    fi
    echo -n "."
    sleep "$sleep_time"
  done
  echo ""
  log_success "SSH is available!"
  return 0
}

# Execute command via SSH
ssh_exec() {
  local cmd="$1"
  local desc="${2:-Running command}"
  
  log_info "$desc..."
  if ! ssh $SSH_OPTS -p $SSH_PORT ${USERNAME}@${HOST_IP} "$cmd"; then
    log_error "Failed: $desc"
    return 1
  fi
  return 0
}

# Execute command with sudo
sudo_exec() {
  local cmd="$1"
  local desc="${2:-Running sudo command}"
  
  # Using stdin redirection to securely pass password
  log_info "$desc..."
  if ! ssh $SSH_OPTS -p $SSH_PORT ${USERNAME}@${HOST_IP} "echo '$PASSWORD' | sudo -S bash -c '$cmd'"; then
    log_error "Failed: $desc"
    return 1
  fi
  return 0
}

# Check tools
for cmd in VBoxManage ssh scp timeout; do
  if ! command -v $cmd &>/dev/null; then
    log_error "'$cmd' must be installed."
    case $cmd in
      VBoxManage) echo "→ Install VirtualBox" ;;
      ssh|scp)    echo "→ Install OpenSSH client" ;;
      timeout)    echo "→ Install coreutils" ;;
    esac
    exit 1
  fi
done

# Get password
PASSWORD=${1:-$DEFAULT_PASSWORD}

echo "=========================================================="
echo -e " ${BOLD}Master Node Setup${RESET}"
echo "=========================================================="
echo " VM Name:   $VM_NAME"
echo " Username:  $USERNAME"
echo " SSH Port:  $SSH_PORT"
echo "=========================================================="

# 1) Clone VM if needed
if ! vm_exists "template"; then
  log_error "'template' VM not found!"
  exit 1
fi

if vm_exists "$VM_NAME"; then
  log_warn "VM '$VM_NAME' already exists. Skipping clone."
else
  log_info "Cloning 'template' → '$VM_NAME'..."
  if ! VBoxManage clonevm template --name "$VM_NAME" --register --mode all; then
    log_error "Failed to clone VM!"
    exit 1
  fi
  log_success "VM cloned successfully."
fi

# 2) Network config
log_info "Configuring network..."
if ! VBoxManage modifyvm "$VM_NAME" --nic2 intnet --intnet2 "$NETWORK_NAME"; then
  log_error "Failed to configure network!"
  exit 1
fi

# Remove any old rule, then add SSH port-forward
VBoxManage modifyvm "$VM_NAME" --natpf1 delete ssh 2>/dev/null || true
if ! VBoxManage modifyvm "$VM_NAME" --natpf1 "ssh,tcp,$HOST_IP,$SSH_PORT,,22"; then
  log_error "Failed to configure port forwarding!"
  exit 1
fi
log_success "Network configured."

# 3) Start VM
if vm_running "$VM_NAME"; then
  log_warn "VM is already running."
else
  log_info "Starting VM in headless mode..."
  if ! VBoxManage startvm "$VM_NAME" --type headless; then
    log_error "Failed to start VM!"
    exit 1
  fi
  log_success "VM started."
fi

# Wait for SSH to become available
if ! wait_for_ssh "$HOST_IP" "$SSH_PORT"; then
  log_error "Could not establish SSH connection to the VM."
  log_info "Try manually: ssh -p $SSH_PORT $USERNAME@$HOST_IP"
  exit 1
fi

# 4) Setup SSH key
log_info "Setting up SSH key authentication..."
if [ ! -f ~/.ssh/id_ed25519 ]; then
  log_info "Generating SSH key..."
  if ! ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""; then
    log_error "Failed to generate SSH key!"
    exit 1
  fi
  log_success "SSH key generated."
fi

# Create ~/.ssh on VM
if ! ssh_exec "mkdir -p ~/.ssh && chmod 700 ~/.ssh" "Creating .ssh directory"; then
  log_error "Failed to create .ssh directory!"
  exit 1
fi

# Copy pubkey
log_info "Copying SSH public key..."
if ! scp -q $SSH_OPTS -P "$SSH_PORT" ~/.ssh/id_ed25519.pub "$USERNAME@$HOST_IP:~/id_ed25519.pub"; then
  log_error "Failed to copy SSH public key!"
  exit 1
fi

# Install pubkey
if ! ssh_exec "cat ~/id_ed25519.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && rm ~/id_ed25519.pub" "Installing public key"; then
  log_error "Failed to install SSH public key!"
  exit 1
fi
log_success "SSH key authentication configured."

# Verify SSH key auth works
log_info "Verifying SSH key authentication..."
if ! ssh -i ~/.ssh/id_ed25519 $SSH_OPTS -p "$SSH_PORT" "$USERNAME@$HOST_IP" "echo 'SSH key auth works!'"; then
  log_error "SSH key authentication verification failed!"
  exit 1
fi
log_success "SSH key authentication verified."

# 5) Copy config files
log_info "Copying configuration directory..."
if [ ! -d master_config ]; then
  log_error "./master_config directory not found!"
  exit 1
fi

if ! scp -q -r $SSH_OPTS -P "$SSH_PORT" master_config "$USERNAME@$HOST_IP:~/"; then
  log_error "Failed to copy configuration files!"
  exit 1
fi
log_success "Configuration files copied."

# 6) Configure inside VM
log_info "Configuring master node inside VM..."

# Network configuration
sudo_exec "cp ~/master_config/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml" "Copying netplan config"
sudo_exec "netplan apply" "Applying network configuration"

# Hostname configuration
sudo_exec "echo '$VM_NAME' > /etc/hostname" "Setting hostname"
sudo_exec "cp ~/master_config/hosts /etc/hosts" "Configuring hosts file"
sudo_exec "hostnamectl set-hostname $VM_NAME" "Setting hostname immediately"

# Install and configure dnsmasq
sudo_exec "apt update && apt install -y dnsmasq" "Installing dnsmasq"
sudo_exec "cp ~/master_config/dnsmasq.conf /etc/dnsmasq.conf" "Configuring dnsmasq"
sudo_exec "mkdir -p /etc/dnsmasq.d" "Creating dnsmasq.d directory"

# Configure DNS resolution
sudo_exec "cp /etc/resolv.conf /etc/resolv.conf.backup 2>/dev/null || true" "Backing up resolv.conf"
sudo_exec "unlink /etc/resolv.conf 2>/dev/null || true" "Removing resolv.conf symlink if exists"
sudo_exec "cp ~/master_config/resolv.conf /etc/resolv.conf" "Setting up new resolv.conf"
sudo_exec "ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.dnsmasq" "Creating resolv.dnsmasq symlink"

# Restart services and enable on boot
sudo_exec "systemctl restart dnsmasq systemd-resolved" "Restarting DNS services"
sudo_exec "systemctl enable dnsmasq" "Enabling dnsmasq on startup"

# Setup NFS server
log_info "Setting up NFS server..."
sudo_exec "apt install -y nfs-kernel-server" "Installing NFS server"
sudo_exec "mkdir -p /shared /shared/data /shared/home" "Creating shared directories"
sudo_exec "chmod 777 /shared /shared/data /shared/home" "Setting permissions on shared directories"
sudo_exec "grep -q '/shared/' /etc/exports || echo '/shared/  192.168.56.0/255.255.255.0(rw,sync,no_root_squash,no_subtree_check)' >> /etc/exports" "Configuring NFS exports"
sudo_exec "systemctl enable nfs-kernel-server" "Enabling NFS server on startup"
sudo_exec "systemctl restart nfs-kernel-server" "Starting NFS server"

log_success "Master node configuration completed."

# 7) Verify configuration 
log_info "Verifying configuration..."

# Check hostname
log_info "Checking hostname..."
HOSTNAME=$(ssh $SSH_OPTS -p "$SSH_PORT" "$USERNAME@$HOST_IP" "hostname" 2>/dev/null)
if [ "$HOSTNAME" != "$VM_NAME" ]; then
  log_warn "Hostname verification failed! Expected '$VM_NAME', got '$HOSTNAME'"
fi

# Verify dnsmasq is running
log_info "Checking dnsmasq service..."
if ! ssh $SSH_OPTS -p "$SSH_PORT" "$USERNAME@$HOST_IP" "systemctl is-active dnsmasq >/dev/null"; then
  log_warn "dnsmasq service is not running!"
fi

# Verify NFS server
log_info "Checking NFS server..."
if ! ssh $SSH_OPTS -p "$SSH_PORT" "$USERNAME@$HOST_IP" "systemctl is-active nfs-kernel-server >/dev/null"; then
  log_warn "NFS server is not running!"
fi

# 8) Reboot
log_info "Rebooting master node..."
sudo_exec "reboot" "Rebooting system"
log_info "Waiting for system to reboot..."
sleep 10

# Wait for VM to come back online
if ! wait_for_ssh "$HOST_IP" "$SSH_PORT"; then
  log_error "Could not reconnect to VM after reboot."
  exit 1
fi

log_success "Master node setup complete!"
log_info "Notes:"
echo -e " - If DNS issues occur after reboot, restart the services with:"
echo -e "   ${BOLD}sudo systemctl restart dnsmasq systemd-resolved${RESET}"
echo
echo -e "Connect to your master node with: ${YELLOW}${BOLD}ssh -i ~/.ssh/id_ed25519 -p $SSH_PORT $USERNAME@$HOST_IP${RESET}"

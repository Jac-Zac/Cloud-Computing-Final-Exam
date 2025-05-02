#!/bin/bash
# Master Node Setup Script
# Usage: ./setup_master.sh [password]

set -e

# Defaults
DEFAULT_PASSWORD="test"
VM_NAME="master"
USERNAME="user01"
SSH_PORT=3022
HOST_IP="127.0.0.1"
NETWORK_NAME="CloudBasicNet"
MAX_RETRIES=10
# REMOVE BatchMode=yes to allow interactive password prompt
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

show_usage() {
  cat <<EOF
Usage: $0 [password]

Arguments:
  password  VM user password (default: $DEFAULT_PASSWORD)

Example:
  $0 mypassword
EOF
}

vm_exists() { VBoxManage list vms | grep -q "\"$1\""; }
vm_running() { VBoxManage showvminfo "$1" 2>/dev/null | grep -q '^State:.*running'; }

wait_for_ssh() {
  local host="$1" port="$2" retries=0 sleep_time=5
  log_info "Waiting for SSH to become available..."
  until ssh $SSH_OPTS -p "$port" "$USERNAME@$host" exit &>/dev/null; do
    ((retries++))
    if ((retries>=MAX_RETRIES)); then
      log_error "Could not connect to SSH after $MAX_RETRIES attempts"; return 1
    fi
    echo -n "."; sleep "$sleep_time"
  done
  echo; log_success "SSH is available!"; return 0
}

ssh_exec() {
  local cmd="$1" desc="${2:-Running command}"
  log_info "$desc..."
  ssh $SSH_OPTS -p $SSH_PORT ${USERNAME}@${HOST_IP} "$cmd" || { log_error "Failed: $desc"; return 1; }
}

sudo_exec() {
  local cmd="$1" desc="${2:-Running sudo command}"
  log_info "$desc..."
  ssh $SSH_OPTS -p $SSH_PORT ${USERNAME}@${HOST_IP} "echo '$PASSWORD' | sudo -S sh -c '$cmd'" \
    || { log_error "Failed: $desc (cmd: $cmd)"; return 1; }
}

# Check required tools
for c in VBoxManage ssh scp timeout; do
  command -v $c &>/dev/null || { log_error "'$c' must be installed."; exit 1; }
done

PASSWORD=${1:-$DEFAULT_PASSWORD}

echo "=========================================================="
echo -e " ${BOLD}Master Node Setup${RESET}"
echo "=========================================================="
echo " VM Name:   $VM_NAME"
echo " Username:  $USERNAME"
echo " SSH Port:  $SSH_PORT"
echo "=========================================================="

# Clone VM if needed
vm_exists "template" || { log_error "'template' VM not found!"; exit 1; }
if ! vm_exists "$VM_NAME"; then
  log_info "Cloning 'template' → '$VM_NAME'..."
  VBoxManage clonevm template --name "$VM_NAME" --register --mode all \
    && log_success "VM cloned successfully." \
    || { log_error "Failed to clone VM!"; exit 1; }
else
  log_warn "VM '$VM_NAME' already exists. Skipping clone."
fi

# Network config
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

# Start VM
if vm_running "$VM_NAME"; then
  log_warn "VM is already running."
else
  log_info "Starting VM in headless mode..."
  VBoxManage startvm "$VM_NAME" --type headless \
    && log_success "VM started." \
    || { log_error "Failed to start VM!"; exit 1; }
fi

# Start VM
if vm_running "$VM_NAME"; then
  log_warn "VM is already running."
else
  log_info "Starting VM in headless mode..."
  VBoxManage startvm "$VM_NAME" --type headless \
    && log_success "VM started." \
    || { log_error "Failed to start VM!"; exit 1; }
fi

# SSH wait
wait_for_ssh "$HOST_IP" "$SSH_PORT" || { log_error "Could not connect via SSH."; exit 1; }

# SSH keys
log_info "Setting up SSH key authentication..."
[ -f ~/.ssh/id_ed25519 ] || (ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" && log_success "SSH key generated.")
ssh_exec "mkdir -p ~/.ssh && chmod 700 ~/.ssh" "Creating .ssh directory"
scp -q $SSH_OPTS -P "$SSH_PORT" ~/.ssh/id_ed25519.pub "${USERNAME}@${HOST_IP}:~/id_ed25519.pub"
ssh_exec "cat ~/id_ed25519.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && rm ~/id_ed25519.pub" "Installing public key"
ssh -i ~/.ssh/id_ed25519 $SSH_OPTS -p "$SSH_PORT" "$USERNAME@$HOST_IP" "echo 'SSH key auth works!'" && log_success "SSH key verified."

# Copy config
log_info "Copying configuration directory..."
[ -d master_config ] || { log_error "./master_config not found!"; exit 1; }
scp -q -r $SSH_OPTS -P "$SSH_PORT" master_config "${USERNAME}@${HOST_IP}:~/" && log_success "Configuration files copied."

# Inside VM setup
log_info "Configuring master node inside VM..."
sudo_exec "cp /home/${USERNAME}/master_config/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml" "Copying netplan config"
sudo_exec "netplan apply" "Applying network configuration"
sudo_exec "echo '$VM_NAME' > /etc/hostname" "Setting hostname"
sudo_exec "cp /home/${USERNAME}/master_config/hosts /etc/hosts" "Configuring hosts file"
sudo_exec "hostnamectl set-hostname $VM_NAME" "Setting hostname immediately"
sudo_exec "apt update && apt install -y dnsmasq" "Installing dnsmasq"
sudo_exec "cp /home/${USERNAME}/master_config/dnsmasq.conf /etc/dnsmasq.conf" "Configuring dnsmasq"
sudo_exec "mkdir -p /etc/dnsmasq.d" "Creating dnsmasq.d directory"
sudo_exec "cp /etc/resolv.conf /etc/resolv.conf.backup 2>/dev/null || true" "Backing up resolv.conf"
sudo_exec "unlink /etc/resolv.conf 2>/dev/null || true" "Removing resolv.conf symlink"
sudo_exec "cp /home/${USERNAME}/master_config/resolv.conf /etc/resolv.conf" "Setting up new resolv.conf"
sudo_exec "ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.dnsmasq" "Creating resolv.dnsmasq symlink"
sudo_exec "systemctl restart dnsmasq systemd-resolved" "Restarting DNS services"
sudo_exec "systemctl enable dnsmasq" "Enabling dnsmasq on startup"

# Make the script executable
sudo_exec "chmod +x /home/${USERNAME}/master_config/fix_dnsmasq_startup.sh" "Making fix script executable"

# Execute the fix script
sudo_exec "/home/${USERNAME}/master_config/fix_dnsmasq_startup.sh" "Running dnsmasq startup fix"

# Verify the fix was applied
ssh_exec "systemctl status dnsmasq" "Verifying dnsmasq configuration" || log_warn "dnsmasq may still have issues!"

# NFS server
log_info "Setting up NFS server..."
sudo_exec "apt install -y nfs-kernel-server" "Installing NFS server"
sudo_exec "mkdir -p /shared /shared/data /shared/home" "Creating shared directories"
sudo_exec "chmod 777 /shared /shared/data /shared/home" "Setting permissions on shared directories"
# Configure exports idempotently
log_info "Configuring NFS exports..."
# Check if /shared/ export exists and is not commented out
if ! ssh $SSH_OPTS -p $SSH_PORT ${USERNAME}@${HOST_IP} "grep -q '^[^#].*/shared/' /etc/exports"; then
  sudo_exec "echo '/shared/  192.168.56.0/255.255.255.0(rw,sync,no_root_squash,no_subtree_check)' >> /etc/exports" "Appending NFS exports"
else
  log_success "NFS exports already present and active"
fi
sudo_exec "systemctl enable nfs-kernel-server" "Enabling NFS server on startup"
sudo_exec "systemctl restart nfs-kernel-server" "Starting NFS server"

log_success "Master node configuration completed."

# Verification & reboot
log_info "Verifying configuration..."
HOSTNAME=$(ssh $SSH_OPTS -p "$SSH_PORT" "$USERNAME@$HOST_IP" hostname)
[ "$HOSTNAME" == "$VM_NAME" ] || log_warn "Hostname mismatch: expected '$VM_NAME', got '$HOSTNAME'"
ssh_exec "systemctl is-active dnsmasq" "Checking dnsmasq service" || log_warn "dnsmasq is not running!"
ssh_exec "systemctl is-active nfs-kernel-server" "Checking NFS server" || log_warn "NFS server is not running!"

log_info "Rebooting master node..."
sudo_exec "reboot" "Rebooting system"
sleep 10
wait_for_ssh "$HOST_IP" "$SSH_PORT" || { log_error "Could not reconnect after reboot."; exit 1; }

log_success "Master node setup complete!"
log_info "Notes:"
echo -e " - If DNS issues occur after reboot, run: sudo systemctl ${BOLD}restart dnsmasq systemd-resolved${RESET}"

echo -e "Connect via: ${YELLOW}${BOLD}ssh -i ~/.ssh/id_ed25519 -p $SSH_PORT $USERNAME@$HOST_IP${RESET}"

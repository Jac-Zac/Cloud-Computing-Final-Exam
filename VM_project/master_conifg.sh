#!/bin/bash
# Extended Node Setup Script
# Usage: ./setup_node.sh [node_name] [ssh_port] [password]

set -e

# Defaults
DEFAULT_NODE_NAME="master"
DEFAULT_SSH_PORT=3022
DEFAULT_PASSWORD="test"
USERNAME="user01"
HOST_IP="127.0.0.1"
NETWORK_NAME="CloudBasicNet"
MAX_RETRIES=10
MASTER_IP="192.168.56.1"  # Master node IP on internal network
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
Usage: $0 [node_name] [ssh_port] [password]

Arguments:
  node_name  Name of the VM to create (default: $DEFAULT_NODE_NAME)
  ssh_port   SSH port to forward on host (default: $DEFAULT_SSH_PORT)
  password   VM user password (default: $DEFAULT_PASSWORD)

Example:
  $0 worker1 3023 mypassword
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
  # Use base64 encoding to avoid quote escaping issues
  cmd_b64=$(echo "$cmd" | base64)
  ssh $SSH_OPTS -p $SSH_PORT ${USERNAME}@${HOST_IP} "echo '$PASSWORD' | sudo -S bash -c \"\$(echo '$cmd_b64' | base64 -d)\"" \
    || { log_error "Failed: $desc (cmd: $cmd)"; return 1; }
}

# Check args
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_usage
  exit 0
fi

# Process arguments
NODE_NAME=${1:-$DEFAULT_NODE_NAME}
SSH_PORT=${2:-$DEFAULT_SSH_PORT}
PASSWORD=${3:-$DEFAULT_PASSWORD}

# Check required tools
for c in VBoxManage ssh scp timeout; do
  command -v $c &>/dev/null || { log_error "'$c' must be installed."; exit 1; }
done

echo "=========================================================="
echo -e " ${BOLD}Node Setup: $NODE_NAME${RESET}"
echo "=========================================================="
echo " VM Name:   $NODE_NAME"
echo " Username:  $USERNAME"
echo " SSH Port:  $SSH_PORT"
echo "=========================================================="

# Clone VM if needed
vm_exists "template" || { log_error "'template' VM not found!"; exit 1; }
if ! vm_exists "$NODE_NAME"; then
  log_info "Cloning 'template' → '$NODE_NAME'..."
  VBoxManage clonevm template --name "$NODE_NAME" --register --mode all \
    && log_success "VM cloned successfully." \
    || { log_error "Failed to clone VM!"; exit 1; }
else
  log_warn "VM '$NODE_NAME' already exists. Skipping clone."
fi

# Network config
log_info "Configuring network..."
# Configure adapter 2 (internal network)
if ! VBoxManage modifyvm "$NODE_NAME" --nic2 intnet --intnet2 "$NETWORK_NAME"; then
  log_error "Failed to configure internal network adapter!"
  exit 1
fi

# Configure adapter 3 (host-only) - only if node is not master
if [[ "$NODE_NAME" != "master" ]]; then
  log_info "Adding host-only adapter for $NODE_NAME..."
  # Get the first host-only interface name
  HOSTONLY_IF=$(VBoxManage list hostonlyifs | grep -m 1 "Name:" | awk '{print $2}')
  
  if [[ -z "$HOSTONLY_IF" ]]; then
    log_info "No host-only interface found. Creating one..."
    VBoxManage hostonlyif create
    HOSTONLY_IF=$(VBoxManage list hostonlyifs | grep -m 1 "Name:" | awk '{print $2}')
  fi
  
  if ! VBoxManage modifyvm "$NODE_NAME" --nic3 hostonly --hostonlyadapter3 "$HOSTONLY_IF"; then
    log_warn "Failed to configure host-only adapter. Continuing without it."
  else
    log_success "Host-only adapter configured: $HOSTONLY_IF"
  fi
fi

# Remove any old rule, then add SSH port-forward
VBoxManage modifyvm "$NODE_NAME" --natpf1 delete ssh 2>/dev/null || true
if ! VBoxManage modifyvm "$NODE_NAME" --natpf1 "ssh,tcp,$HOST_IP,$SSH_PORT,,22"; then
  log_error "Failed to configure port forwarding!"
  exit 1
fi

log_success "Network configured."

# Start VM
if vm_running "$NODE_NAME"; then
  log_warn "VM is already running."
else
  log_info "Starting VM in headless mode..."
  VBoxManage startvm "$NODE_NAME" --type headless \
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

# Copy config directory
CONFIG_DIR="${NODE_NAME}_config"
if [[ "$NODE_NAME" == "master" && -d "master_config" ]]; then
  CONFIG_DIR="master_config"
elif [[ -d "${NODE_NAME}_config" ]]; then
  CONFIG_DIR="${NODE_NAME}_config"
else
  # If no specific config exists, use default config
  if [[ -d "node_config" ]]; then
    CONFIG_DIR="node_config"
    log_warn "Using generic node configuration directory."
  else
    log_error "Configuration directory for ${NODE_NAME} not found!"
    log_info "Please create either '${NODE_NAME}_config' or 'node_config' directory."
    exit 1
  fi
fi

log_info "Copying configuration directory ($CONFIG_DIR)..."
scp -q -r $SSH_OPTS -P "$SSH_PORT" "$CONFIG_DIR" "${USERNAME}@${HOST_IP}:~/" && log_success "Configuration files copied."

# Inside VM setup - common for all nodes
log_info "Configuring node inside VM..."
sudo_exec "cp /home/${USERNAME}/$CONFIG_DIR/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml" "Copying netplan config"
sudo_exec "netplan apply" "Applying network configuration"

# Only set hostname for master node, worker will get hostname from DHCP
if [[ "$NODE_NAME" == "master" ]]; then
  sudo_exec "echo '$NODE_NAME' > /etc/hostname" "Setting hostname"
  sudo_exec "hostnamectl set-hostname $NODE_NAME" "Setting hostname immediately"
else
  # For worker nodes, clear the hostname to allow DHCP assignment
  sudo_exec "echo '' > /etc/hostname" "Clearing hostname for DHCP assignment"
fi

sudo_exec "cp /home/${USERNAME}/$CONFIG_DIR/hosts /etc/hosts" "Configuring hosts file"

# Special configuration for master node
if [[ "$NODE_NAME" == "master" ]]; then
  log_info "Configuring master-specific services..."
  
  # DNSMASQ
  sudo_exec "apt update && apt install -y dnsmasq" "Installing dnsmasq"
  sudo_exec "cp /home/${USERNAME}/$CONFIG_DIR/dnsmasq.conf /etc/dnsmasq.conf" "Configuring dnsmasq"
  sudo_exec "mkdir -p /etc/dnsmasq.d" "Creating dnsmasq.d directory"
  sudo_exec "cp /etc/resolv.conf /etc/resolv.conf.backup 2>/dev/null || true" "Backing up resolv.conf"
  sudo_exec "unlink /etc/resolv.conf 2>/dev/null || true" "Removing resolv.conf symlink"
  sudo_exec "cp /home/${USERNAME}/$CONFIG_DIR/resolv.conf /etc/resolv.conf" "Setting up new resolv.conf"
  sudo_exec "ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.dnsmasq" "Creating resolv.dnsmasq symlink"
  sudo_exec "systemctl restart dnsmasq systemd-resolved" "Restarting DNS services"
  sudo_exec "systemctl enable dnsmasq" "Enabling dnsmasq on startup"

  # Make the script executable if it exists
  if ssh_exec "test -f /home/${USERNAME}/$CONFIG_DIR/fix_dnsmasq_startup.sh && echo 'exists'" &>/dev/null; then
    sudo_exec "chmod +x /home/${USERNAME}/$CONFIG_DIR/fix_dnsmasq_startup.sh" "Making fix script executable"
    sudo_exec "/home/${USERNAME}/$CONFIG_DIR/fix_dnsmasq_startup.sh" "Running dnsmasq startup fix"
    ssh_exec "systemctl status dnsmasq" "Verifying dnsmasq configuration" || log_warn "dnsmasq may still have issues!"
  fi

  # NFS server
  log_info "Setting up NFS server..."
  sudo_exec "apt install -y nfs-kernel-server" "Installing NFS server"
  sudo_exec "mkdir -p /shared /shared/data /shared/home" "Creating shared directories"
  sudo_exec "chmod 777 /shared /shared/data /shared/home" "Setting permissions on shared directories"
  
  # Configure exports idempotently
  log_info "Configuring NFS exports..."
  # Check if /shared/ export exists and is not commented out
  if ! ssh $SSH_OPTS -p $SSH_PORT ${USERNAME}@${HOST_IP} "grep -q '^[^#].*/shared/' /etc/exports"; then
    sudo_exec 'echo "/shared/  192.168.56.0/255.255.255.0(rw,sync,no_root_squash,no_subtree_check)" >> /etc/exports' "Appending NFS exports"
  else
    log_success "NFS exports already present and active"
  fi
  sudo_exec "systemctl enable nfs-kernel-server" "Enabling NFS server on startup"
  sudo_exec "systemctl restart nfs-kernel-server" "Starting NFS server"
else
  # Worker node specific configuration
  log_info "Configuring worker node services..."
  
  # Configure DNS resolution
  sudo_exec "unlink /etc/resolv.conf 2>/dev/null || true" "Removing resolv.conf symlink"
  sudo_exec "cp /home/${USERNAME}/$CONFIG_DIR/resolv.conf /etc/resolv.conf" "Setting up resolv.conf to use master as DNS"
  
  # NFS client setup
  sudo_exec "apt update && apt install -y nfs-common autofs" "Installing NFS client and AutoFS"
  sudo_exec "mkdir -p /shared/data /shared/home" "Creating shared mount points"
  
  # Configure AutoFS for automatic mounting
  sudo_exec "echo '/shared /etc/auto.shared' | tee -a /etc/auto.master > /dev/null" "Setting up AutoFS master configuration"
  sudo_exec "echo '# create new : [mount point] [option] [location]' | tee /etc/auto.shared > /dev/null" "Creating AutoFS shared configuration"
  sudo_exec "echo 'data    -fstype=nfs,rw,soft,intr    ${MASTER_IP}:/shared/data' | tee -a /etc/auto.shared > /dev/null" "Adding data share to AutoFS"
  sudo_exec "echo 'home    -fstype=nfs,rw,soft,intr    ${MASTER_IP}:/shared/home' | tee -a /etc/auto.shared > /dev/null" "Adding home share to AutoFS"
  
  # Start and enable AutoFS
  sudo_exec "systemctl restart autofs" "Restarting AutoFS service"
  sudo_exec "systemctl enable autofs" "Enabling AutoFS on startup"
  
  # Alternative direct mount for testing
  sudo_exec "mkdir -p /mnt/shared_test" "Creating test mount point"
  sudo_exec "mount -t nfs ${MASTER_IP}:/shared/data /mnt/shared_test || true" "Testing direct NFS mount"
fi

# Verification & reboot
log_info "Verifying configuration..."
HOSTNAME=$(ssh $SSH_OPTS -p "$SSH_PORT" "$USERNAME@$HOST_IP" hostname)
[ "$HOSTNAME" == "$NODE_NAME" ] || log_warn "Hostname mismatch: expected '$NODE_NAME', got '$HOSTNAME'"

if [[ "$NODE_NAME" == "master" ]]; then
  ssh_exec "systemctl is-active dnsmasq" "Checking dnsmasq service" || log_warn "dnsmasq is not running!"
  ssh_exec "systemctl is-active nfs-kernel-server" "Checking NFS server" || log_warn "NFS server is not running!"
fi

log_info "Rebooting node..."
sudo_exec "reboot" "Rebooting system"
sleep 10
wait_for_ssh "$HOST_IP" "$SSH_PORT" || { log_error "Could not reconnect after reboot."; exit 1; }

log_success "$NODE_NAME node setup complete!"

if [[ "$NODE_NAME" == "master" ]]; then
  log_info "Master node notes:"
  echo -e " - If DNS issues occur after reboot, run: sudo systemctl ${BOLD}restart dnsmasq systemd-resolved${RESET}"
  echo -e " - To verify NFS exports: ${BOLD}showmount -e localhost${RESET}"
  echo -e " - Worker nodes can be accessed via: ${BOLD}ssh ${USERNAME}@node-XX${RESET} (where XX is the node number)"
else
  log_info "Worker node notes:"
  echo -e " - NFS should automatically mount when accessing /shared/data or /shared/home"
  echo -e " - Verify AutoFS mounts with: ${BOLD}ls -la /shared/data${RESET}"
  echo -e " - Check connectivity to master with: ${BOLD}ping master${RESET}"
  echo -e " - Verify hostname assignment with: ${BOLD}hostname${RESET}"
  echo -e " - Check available NFS exports with: ${BOLD}showmount -e ${MASTER_IP}${RESET}"
  echo -e " - Generate SSH keys with: ${BOLD}ssh-keygen${RESET} for passwordless access between nodes"
fi

# Add node status monitoring script
if [[ "$NODE_NAME" == "master" ]]; then
  log_info "Creating node status monitoring script..."
  cat > /tmp/check_nodes.sh <<EOF
#!/bin/bash
# Node status monitoring script
echo "Checking node status:"
for node in master node-01 node-02; do
  echo -n "\$node: "
  ping -c 1 -W 1 \$node >/dev/null && echo "UP" || echo "DOWN"
done
EOF
  scp -q $SSH_OPTS -P "$SSH_PORT" /tmp/check_nodes.sh "${USERNAME}@${HOST_IP}:~/"
  sudo_exec "mkdir -p /shared/scripts" "Creating shared scripts directory"
  sudo_exec "cp /home/${USERNAME}/check_nodes.sh /shared/scripts/" "Copying monitoring script to shared location"
  sudo_exec "chmod +x /shared/scripts/check_nodes.sh" "Making monitoring script executable"
  log_success "Node monitoring script created at /shared/scripts/check_nodes.sh"
fi

echo -e "Connect via: ${YELLOW}${BOLD}ssh -i ~/.ssh/id_ed25519 -p $SSH_PORT $USERNAME@$HOST_IP${RESET}"

#!/bin/bash
# Improved Node Setup Script with sshpass and passwordless sudo
# Usage: ./setup_node.sh [node_name] [ssh_port] [password]

set -e

# Defaults
DEFAULT_NODE_NAME="master"
DEFAULT_SSH_PORT=3022
DEFAULT_SSH_MASTER_PORT=3022  # Master node's SSH port
DEFAULT_PASSWORD="test"
USERNAME="user01"
HOST_IP="127.0.0.1"
NETWORK_NAME="CloudBasicNet"
MAX_RETRIES=15  # Increased for longer wait periods
MASTER_IP="192.168.56.1"  # Master node IP on internal network
# SSH options with no StrictHostKeyChecking
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
  until sshpass -p "$PASSWORD" ssh $SSH_OPTS -p "$port" "$USERNAME@$host" exit &>/dev/null; do
    ((retries++))
    if ((retries>=MAX_RETRIES)); then
      log_error "Could not connect to SSH after $MAX_RETRIES attempts"; return 1
    fi
    echo -n "."; sleep "$sleep_time"
  done
  echo; log_success "SSH is available!"; return 0
}

# Function to ensure master node is running
ensure_master_running() {
  if [[ "$NODE_NAME" != "master" ]]; then
    log_info "Checking if master node exists and is running..."
    if ! vm_exists "master"; then
      log_error "Master node VM doesn't exist! Please set up the master node first."
      exit 1
    fi
    
    if ! vm_running "master"; then
      log_info "Starting master node VM..."
      VBoxManage startvm "master" --type headless
      
      # Wait for master node to be accessible via SSH
      wait_for_ssh "$HOST_IP" "$DEFAULT_SSH_MASTER_PORT" || {
        log_error "Could not connect to master node via SSH."
        exit 1
      }
      
      # Give master a bit more time to fully start services
      log_info "Waiting for master node services to initialize..."
      sleep 15
    else
      log_success "Master node is already running."
    fi
  fi
}

ssh_exec() {
  local cmd="$1" desc="${2:-Running command}"
  log_info "$desc..."
  sshpass -p "$PASSWORD" ssh $SSH_OPTS -p $SSH_PORT ${USERNAME}@${HOST_IP} "$cmd" || { log_error "Failed: $desc"; return 1; }
}

ssh_exec_master() {
  local cmd="$1" desc="${2:-Running command on master}"
  log_info "$desc..."
  sshpass -p "$PASSWORD" ssh $SSH_OPTS -p $DEFAULT_SSH_MASTER_PORT ${USERNAME}@${HOST_IP} "$cmd" || { log_error "Failed: $desc"; return 1; }
}

sudo_exec() {
  local cmd="$1" desc="${2:-Running sudo command}"
  log_info "$desc..."
  # Use base64 encoding to avoid quote escaping issues
  cmd_b64=$(echo "$cmd" | base64)
  sshpass -p "$PASSWORD" ssh $SSH_OPTS -p $SSH_PORT ${USERNAME}@${HOST_IP} "echo '$PASSWORD' | sudo -S bash -c \"\$(echo '$cmd_b64' | base64 -d)\"" \
    || { log_error "Failed: $desc (cmd: $cmd)"; return 1; }
}

sudo_exec_master() {
  local cmd="$1" desc="${2:-Running sudo command on master}"
  log_info "$desc..."
  # Use base64 encoding to avoid quote escaping issues
  cmd_b64=$(echo "$cmd" | base64)
  sshpass -p "$PASSWORD" ssh $SSH_OPTS -p $DEFAULT_SSH_MASTER_PORT ${USERNAME}@${HOST_IP} "echo '$PASSWORD' | sudo -S bash -c \"\$(echo '$cmd_b64' | base64 -d)\"" \
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
for c in VBoxManage ssh scp timeout sshpass; do
  if ! command -v $c &>/dev/null; then
    log_error "'$c' must be installed."
    if [[ "$c" == "sshpass" ]]; then
      echo "Install sshpass using:"
      echo "  Ubuntu/Debian: sudo apt-get install sshpass"
      echo "  macOS:         brew install sshpass"
      echo "  Fedora/RHEL:   sudo dnf install sshpass"
    fi
    exit 1
  fi
done

echo "=========================================================="
echo -e " ${BOLD}Node Setup: $NODE_NAME${RESET}"
echo "=========================================================="
echo " VM Name:   $NODE_NAME"
echo " Username:  $USERNAME"
echo " SSH Port:  $SSH_PORT"
echo "=========================================================="

# For non-master nodes, ensure master is running first
if [[ "$NODE_NAME" != "master" ]]; then
  ensure_master_running
fi

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

# SSH keys - Only set up for master node
if [[ "$NODE_NAME" == "master" ]]; then
  log_info "Setting up SSH key authentication for master node..."
  # Check if local SSH key exists, if not generate it
  [ -f ~/.ssh/id_ed25519 ] || (ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" && log_success "SSH key generated.")
  
  # Copy the local SSH key to master node
  ssh_exec "mkdir -p ~/.ssh && chmod 700 ~/.ssh" "Creating .ssh directory on master"
  sshpass -p "$PASSWORD" scp -q $SSH_OPTS -P "$SSH_PORT" ~/.ssh/id_ed25519.pub "${USERNAME}@${HOST_IP}:~/id_ed25519.pub"
  ssh_exec "cat ~/id_ed25519.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && rm ~/id_ed25519.pub" "Installing public key on master"
  ssh -i ~/.ssh/id_ed25519 $SSH_OPTS -p "$SSH_PORT" "$USERNAME@$HOST_IP" "echo 'SSH key auth works!'" && log_success "SSH key verified on master."
fi
# For worker nodes, we'll skip this step as they'll only be accessible from master

# Copy config directory
if [[ "$NODE_NAME" == "master" && -d "master_config" ]]; then
  CONFIG_DIR="master_config"
else
  # If no specific config exists, use default config
  CONFIG_DIR="node_config"
fi

log_info "Copying configuration directory ($CONFIG_DIR)..."
sshpass -p "$PASSWORD" scp -q -r $SSH_OPTS -P "$SSH_PORT" "$CONFIG_DIR" "${USERNAME}@${HOST_IP}:~/" && log_success "Configuration files copied."

# Setup passwordless sudo
log_info "Setting up passwordless sudo..."
# Create a sudoers file to allow passwordless sudo
sudo_exec "bash -c \"echo '$USERNAME ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$USERNAME && chmod 440 /etc/sudoers.d/$USERNAME\"" "Configuring passwordless sudo"

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

# Special configuration for master node
if [[ "$NODE_NAME" == "master" ]]; then
  sudo_exec "cp /home/${USERNAME}/$CONFIG_DIR/hosts /etc/hosts" "Configuring hosts file"
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
  sudo_exec "mkdir -p /shared /shared/data /shared/home /shared/ssh-keys /shared/scripts" "Creating shared directories"
  sudo_exec "chmod 777 /shared /shared/data /shared/home /shared/ssh-keys /shared/scripts" "Setting permissions on shared directories"
  
  # Configure exports idempotently
  log_info "Configuring NFS exports..."
  # Check if /shared/ export exists and is not commented out
  if ! sshpass -p "$PASSWORD" ssh $SSH_OPTS -p $SSH_PORT ${USERNAME}@${HOST_IP} "grep -q '^[^#].*/shared/' /etc/exports"; then
    sudo_exec 'echo "/shared/  192.168.56.0/255.255.255.0(rw,sync,no_root_squash,no_subtree_check)" >> /etc/exports' "Appending NFS exports"
  else
    log_success "NFS exports already present and active"
  fi
  sudo_exec "systemctl enable nfs-kernel-server" "Enabling NFS server on startup"
  sudo_exec "systemctl restart nfs-kernel-server" "Starting NFS server"
  
  # Create SSH key on master if it doesn't exist
  ssh_exec "[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ''" "Creating SSH key on master"
  
  # Store master's public key in shared directory for nodes to use
  ssh_exec "cp ~/.ssh/id_ed25519.pub /shared/ssh-keys/master.pub" "Copying master's public key to shared directory"
  
else
  # Worker node specific configuration
  log_info "Configuring worker node services..."
  
  # Configure DNS resolution
  sudo_exec "unlink /etc/resolv.conf 2>/dev/null || true" "Removing resolv.conf symlink"
  sudo_exec "cp /home/${USERNAME}/$CONFIG_DIR/resolv.conf /etc/resolv.conf" "Setting up resolv.conf to use master as DNS"
  
  # NFS client setup
  sudo_exec "apt update && apt install -y nfs-common autofs" "Installing NFS client and AutoFS"
  sudo_exec "mkdir -p /shared/data /shared/home /shared/ssh-keys" "Creating shared mount points"
  
  # Configure AutoFS for automatic mounting
  sudo_exec "echo '/-      /etc/auto.shared' | tee -a /etc/auto.master > /dev/null" "Setting up AutoFS master configuration"
  sudo_exec "echo '/shared    master:/shared' | tee /etc/auto.shared > /dev/null" "Creating AutoFS shared configuration"
  
  # Start and enable AutoFS
  sudo_exec "systemctl enable autofs" "Enabling AutoFS on startup"
  sudo_exec "systemctl restart autofs" "Restarting AutoFS service"
fi

# Verification & reboot
log_info "Verifying configuration..."
HOSTNAME=$(sshpass -p "$PASSWORD" ssh $SSH_OPTS -p "$SSH_PORT" "$USERNAME@$HOST_IP" hostname)
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

# For worker nodes, handle SSH key setup so master can access worker nodes
if [[ "$NODE_NAME" != "master" ]]; then
  log_info "Waiting for DHCP hostname assignment..."
  sleep 60  # Give time for full network initialization after reboot
  
  # Get assigned hostname from DHCP
  ASSIGNED_HOSTNAME=$(sshpass -p "$PASSWORD" ssh $SSH_OPTS -p "$SSH_PORT" "$USERNAME@$HOST_IP" hostname)
  log_success "Node was assigned hostname: $ASSIGNED_HOSTNAME"
  
  # Setup authorized_keys on worker to allow master to SSH in
  log_info "Setting up SSH access from master to worker..."
  ssh_exec "mkdir -p ~/.ssh && chmod 700 ~/.ssh" "Ensuring worker's .ssh directory exists"
  
  # Copy master's public key to worker's authorized_keys
  ssh_exec "cp /shared/ssh-keys/master.pub ~/.ssh/ && cat ~/.ssh/master.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" "Adding master's key to worker's authorized_keys"
  
  # Test SSH connectivity from master to worker
  log_info "Testing SSH connectivity from master to worker..."
  ssh_exec_master "ssh $SSH_OPTS ${ASSIGNED_HOSTNAME} 'echo \"SSH from master to ${ASSIGNED_HOSTNAME} works!\"'" "Testing SSH from master to worker"
  
  log_success "Master to worker SSH access configured successfully!"
fi

# Add node status monitoring script
if [[ "$NODE_NAME" == "master" ]]; then
  log_info "Deploying node status monitoring script..."

  # Move script from copied master_config to shared location
  sudo_exec "cp /home/${USERNAME}/master_config/check_node.sh /shared/scripts/" "Copying monitoring script to shared location"
  sudo_exec "chmod +x /shared/scripts/check_node.sh" "Making monitoring script executable"

  log_info "Copy Scripts to test performances..."
  sshpass -p "$PASSWORD" scp -q -r $SSH_OPTS -P "$SSH_PORT" "../Containers/Performance_Testing/" "${USERNAME}@${HOST_IP}:/shared/" && log_success "Performance testing script copied"

  log_success "Node monitoring script deployed to /shared/scripts/check_node.sh"
fi

# Final notes
if [[ "$NODE_NAME" == "master" ]]; then
  log_info "Master node notes:"
  echo -e " - If DNS issues occur after reboot, run: sudo systemctl ${BOLD}restart dnsmasq systemd-resolved${RESET}"
  echo -e " - To verify NFS exports: ${BOLD}showmount -e localhost${RESET}"
  echo -e " - Worker nodes can be accessed via: ${BOLD}ssh ${ASSIGNED_HOSTNAME}${RESET} (using hostname assigned by DHCP)"
  # SSH connection info for master node only
  echo -e "Connect to master via: ${YELLOW}${BOLD}ssh -i ~/.ssh/id_ed25519 -p $SSH_PORT $USERNAME@$HOST_IP${RESET}"
  echo -e "Or using password: ${YELLOW}${BOLD}sshpass -p \"$PASSWORD\" ssh -p $SSH_PORT $USERNAME@$HOST_IP${RESET}"
else
  log_info "Worker node notes:"
  echo -e " - NFS should automatically mount when accessing /shared/data or /shared/home"
  echo -e " - Verify AutoFS mounts with: ${BOLD}ls -la /shared/data${RESET}"
  echo -e " - Check connectivity to master with: ${BOLD}ping master${RESET}"
  echo -e " - Verify hostname assignment with: ${BOLD}hostname${RESET}" 
  echo -e " - Access worker nodes by first SSHing to master, then: ${BOLD}ssh ${ASSIGNED_HOSTNAME}${RESET}"
  echo -e " - ${YELLOW}${BOLD}Note: Worker nodes are not directly accessible from your local machine${RESET}"
fi

log_success "Setup completed with sshpass integration and passwordless sudo enabled!"

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

# Check tools
for cmd in VBoxManage ssh scp; do
  if ! command -v $cmd &>/dev/null; then
    echo "Error: '$cmd' must be installed." >&2
    case $cmd in
      VBoxManage) echo "→ Install VirtualBox" ;;
      ssh|scp)    echo "→ Install OpenSSH client" ;;
    esac
    exit 1
  fi
done

# Get password
PASSWORD=${1:-$DEFAULT_PASSWORD}

echo "=========================================================="
echo " Master Node Setup"
echo "=========================================================="
echo " VM Name:   $VM_NAME"
echo " Username:  $USERNAME"
echo " SSH Port:  $SSH_PORT"
echo "=========================================================="

# 1) Clone VM if needed
if ! VBoxManage list vms | grep -q "\"template\""; then
  echo "Error: 'template' VM not found!" >&2
  exit 1
fi
if VBoxManage list vms | grep -q "\"$VM_NAME\""; then
  echo "VM '$VM_NAME' already exists. Skipping clone."
else
  echo "Cloning 'template' → '$VM_NAME'..."
  VBoxManage clonevm template --name "$VM_NAME" --register --mode all
  echo "Cloned."
fi

# 2) Network config
echo "Configuring network..."
VBoxManage modifyvm "$VM_NAME" --nic2 intnet \
                               --intnet2 "$NETWORK_NAME"
# Remove any old rule, then add SSH port-forward
VBoxManage modifyvm "$VM_NAME" --natpf1 delete ssh    2>/dev/null || true
VBoxManage modifyvm "$VM_NAME" --natpf1 "ssh,tcp,$HOST_IP,$SSH_PORT,,22"
echo "Network done."

# 3) Start VM
if VBoxManage showvminfo "$VM_NAME" | grep -q '^State:.*running'; then
  echo "Already running."
else
  echo "Starting headless..."
  VBoxManage startvm "$VM_NAME" --type headless
  echo "Waiting 120s for boot..."
  sleep 120
fi

# 4) Setup SSH key (manual copy → no R, no ssh-copy-id)
echo "Setting up SSH key auth..."
[ -f ~/.ssh/id_ed25519 ] || \
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" \
    && echo "Generated key."

# Create ~/.ssh on VM
ssh -T -o StrictHostKeyChecking=no -p "$SSH_PORT" \
    "$USERNAME@$HOST_IP" "mkdir -p ~/.ssh && chmod 700 ~/.ssh"

# Copy pubkey
scp -P "$SSH_PORT" ~/.ssh/id_ed25519.pub \
    "$USERNAME@$HOST_IP:~/id_ed25519.pub"

# Install pubkey
ssh -T -o StrictHostKeyChecking=no -p "$SSH_PORT" \
    "$USERNAME@$HOST_IP" "
  cat ~/id_ed25519.pub >> ~/.ssh/authorized_keys &&
  chmod 600 ~/.ssh/authorized_keys &&
  rm ~/id_ed25519.pub
"
echo "SSH key setup complete."

# 5) Copy config files
echo "Copying config directory..."
if [ ! -d master_config ]; then
  echo "Error: ./master_config not found!" >&2
  exit 1
fi
scp -o StrictHostKeyChecking=no -P "$SSH_PORT" \
    -r master_config "$USERNAME@$HOST_IP:~/"
echo "Copied."

# 6) Configure inside VM (sudo via -S, no TTY)
echo "Configuring master node inside VM..."
ssh -T -o StrictHostKeyChecking=no -p "$SSH_PORT" \
    "$USERNAME@$HOST_IP" "
  set -e
  echo '$PASSWORD' | sudo -S cp  ~/master_config/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml
  echo '$PASSWORD' | sudo -S netplan apply

  echo '$PASSWORD' | sudo -S tee /etc/hostname <<< '$VM_NAME' >/dev/null
  echo '$PASSWORD' | sudo -S cp  ~/master_config/hosts /etc/hosts

  echo '$PASSWORD' | sudo -S apt update
  echo '$PASSWORD' | sudo -S apt install -y dnsmasq
  echo '$PASSWORD' | sudo -S cp  ~/master_config/dnsmasq.conf /etc/dnsmasq.conf

  echo '$PASSWORD' | sudo -S unlink /etc/resolv.conf 2>/dev/null || true
  echo '$PASSWORD' | sudo -S cp  ~/master_config/resolv.conf  /etc/resolv.conf
  echo '$PASSWORD' | sudo -S ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.dnsmasq

  echo '$PASSWORD' | sudo -S systemctl restart dnsmasq systemd-resolved
  echo '$PASSWORD' | sudo -S systemctl enable  dnsmasq
"
echo "Master node configured."

# 7) Reboot
echo "Rebooting master..."
ssh -T -o StrictHostKeyChecking=no -p "$SSH_PORT" \
    "$USERNAME@$HOST_IP" "
  echo '$PASSWORD' | sudo -S reboot
"
echo "Done. Connect with: ssh -i ~/.ssh/id_ed25519 -p $SSH_PORT $USERNAME@$HOST_IP"


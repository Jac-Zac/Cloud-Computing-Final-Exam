#!/bin/bash

set -e

echo "Creating systemd override for dnsmasq to start after network-online.target..."

# Create override directory if it doesn't exist
sudo mkdir -p /etc/systemd/system/dnsmasq.service.d

# Write the override file
sudo tee /etc/systemd/system/dnsmasq.service.d/override.conf > /dev/null <<EOF
[Unit]
After=network-online.target
Wants=network-online.target
EOF

echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "Restarting dnsmasq service..."
sudo systemctl restart dnsmasq

echo "Restarting systemd-resolved service..."
sudo systemctl restart systemd-resolved

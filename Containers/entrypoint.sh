#!/bin/bash
set -e

echo "Container starting with role: $NODE_ROLE"

mkdir -p /root/.ssh

if [ "$NODE_ROLE" = "master" ]; then
    # Generate SSH key for root if not exists
    if [ ! -f /root/.ssh/id_rsa ]; then
        echo "Generating SSH key..."
        ssh-keygen -t rsa -f /root/.ssh/id_rsa -q -N ""
    fi

    # Copy public key to shared volume
    cp /root/.ssh/id_rsa.pub /shared/master.pub
    echo "Master public key written to /shared/master.pub"

else
    # Wait until master's public key is available
    echo "Waiting for master's public key..."
    while [ ! -f /shared/master.pub ]; do
        sleep 1
    done

    # Append master's public key to authorized_keys
    cat /shared/master.pub >> /root/.ssh/authorized_keys
    echo "Master public key added to authorized_keys"
fi

# Ensure correct permissions
chmod 700 /root/.ssh
chmod 600 /root/.ssh/*

# Start SSH server in foreground
exec /usr/sbin/sshd -D

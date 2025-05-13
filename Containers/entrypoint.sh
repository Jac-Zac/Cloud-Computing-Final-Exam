#!/bin/bash
# Script to enable master to access the other containers via ssh
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

# SSHD runs in foreground, container stays up
exec /usr/sbin/sshd -D

--- TO REVIRW
#!/bin/bash
# entrypoint.sh - Docker container entrypoint script

# Start SSH service
/usr/sbin/sshd

# Generate hostfile for MPI based on role
if [ "$NODE_ROLE" = "master" ]; then
    echo "🔧 Setting up master node..."
    
    # Create MPI hostfile with fixed IPs
    echo "# Auto-generated MPI hostfile" > /benchmark/mpi-hostfile
    echo "master slots=2" >> /benchmark/mpi-hostfile
    echo "node-01 slots=2" >> /benchmark/mpi-hostfile
    echo "node-02 slots=2" >> /benchmark/mpi-hostfile
    
    echo "✅ Master node setup complete."
    echo "👉 To run benchmarks: docker exec -it master bash -c 'cd /benchmark && ./run-all.sh master container master'"
    
    # Keep container running
    tail -f /dev/null
else
    echo "🔧 Setting up worker node..."
    echo "✅ Worker node ready."
    
    # Keep container running
    tail -f /dev/null
fi

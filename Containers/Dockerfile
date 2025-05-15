FROM ubuntu:22.04

# Set non-interactive mode for apt
ENV DEBIAN_FRONTEND=noninteractive

# Install essential packages
RUN apt-get update && apt-get install -y \
    openssh-server \
    sshpass \
    sudo \
    sysbench \
    iozone3 \
    iperf3 \
    openmpi-bin \
    hpcc \
    stress-ng \
    python3 \
    python3-pip \
    netcat \
    htop \
    vim \
    git \
    build-essential \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Setup SSH
RUN mkdir /var/run/sshd
# Generate SSH host keys
RUN ssh-keygen -A
# Setup passwordless SSH (for MPI)
RUN mkdir -p /root/.ssh
RUN ssh-keygen -t rsa -f /root/.ssh/id_rsa -N ""
RUN cat /root/.ssh/id_rsa.pub > /root/.ssh/authorized_keys
RUN chmod 600 /root/.ssh/authorized_keys

# Trust all hosts (for simplicity in test env)
RUN echo "Host *\n\tStrictHostKeyChecking no\n\tUserKnownHostsFile /dev/null" > /root/.ssh/config

# Copy all the performance testing
COPY Performance_Testing/ ./Performance_Testing/

# Add entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose SSH port
EXPOSE 22

# Start SSH server and keep container running
ENTRYPOINT ["/entrypoint.sh"]

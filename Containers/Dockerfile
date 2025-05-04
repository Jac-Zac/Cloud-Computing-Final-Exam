FROM ubuntu:20.04

WORKDIR /app

ENV DEBIAN_FRONTEND=noninteractive

# Install SSH, netcat (for healthcheck), and benchmarking tools
RUN apt-get update && \
    apt-get install -y openssh-server netcat iproute2 \
    sysbench iozone3 iperf3 build-essential libopenmpi-dev openmpi-bin hpcc && \
    apt-get clean

# Create SSH run directory
RUN mkdir -p /var/run/sshd

# Allow root login via passwordless SSH
RUN echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    echo 'StrictHostKeyChecking no' >> /etc/ssh/ssh_config

# Create shared directory mount point
RUN mkdir -p /shared

# Add benchmark script
COPY ../Performance_Testing/benchmark.sh /app/benchmark.sh
RUN chmod +x /app/benchmark.sh

# Add entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy HPL configuration
COPY ../Performance_Testing/HPL.dat /app/HPL.dat

# Expose SSH port
EXPOSE 22

# Run the entrypoint script
ENTRYPOINT ["/entrypoint.sh"]

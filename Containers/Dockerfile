FROM ubuntu:20.04

# Mayybe I should set a workdirectory

ENV DEBIAN_FRONTEND=noninteractive

# Install SSH, netcat (for healthcheck), and other basics
RUN apt-get update && \
    apt-get install -y openssh-server netcat iproute2 && \
    apt-get clean

# Create SSH run directory
RUN mkdir -p /var/run/sshd

# Allow root login via passwordless SSH
RUN echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    echo 'StrictHostKeyChecking no' >> /etc/ssh/ssh_config

# Create shared directory mount point
RUN mkdir -p /shared

# Add entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose SSH port
EXPOSE 22

# Run the entrypoint script
ENTRYPOINT ["/entrypoint.sh"]


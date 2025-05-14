# HPC Docker Cluster Setup

This project sets up a lightweight HPC-like environment using Docker containers, with one **master** and two **worker nodes**. It enables SSH communication and MPI benchmark execution using a shared volume and predefined IP addresses.

---

## 📁 Project Structure

```
.
├── Dockerfile
├── compose.yaml
├── entrypoint.sh
├── benchmark/
├── results/
│   ├── master/
│   ├── node-01/
│   └── node-02/
└── shared/ (Docker-managed volume)
```

## 🚀 Getting Started

### 1. Clone the repository

```bash
git clone <your-repo-url>
cd <repo-directory>
```

### 2. Make `entrypoint.sh` executable

```bash
chmod +x entrypoint.sh
```

### 3. Build and Start the Cluster

```bash
docker-compose -f compose.yaml up --build
```

Each node has a limit of 2 CPU cores. However, on macOS, core pinning for Docker containers using the `--cpuset-cpus` option is not effective because Docker Desktop for Mac runs containers inside a lightweight VM, which abstracts the host CPU cores.
As a result, pinning containers to specific cores does not actually restrict CPU usage to those cores on a Mac

This starts three containers:

- `master`: Master node: which can ssh in other machines
- `node-01`: Worker node
- `node-02`: Worker node

The master generates an SSH key and shares it with workers via a Docker-managed volume `hpc-shared`.

## 🔐 SSH Communication

> Following a similar structure to what has been done in VMS

- The master node generates a root SSH keypair if not already present.
- Workers wait until the master's public key is available, then append it to their `authorized_keys`.
- SSH daemon is started in each container.

## 🖥️ MPI Hostfile Generation

On the `master` node:

- A hostfile is created at `/benchmark/configs/mpi-hostfile` with fixed IP aliases.
- Format:

  ```
  # Auto-generated MPI hostfile
  master slots=2
  node-01 slots=2
  node-02 slots=2
  ```

## 📊 Running Benchmarks

Once all containers are up, run benchmarks from the master node:

```bash
docker exec -it master bash
cd /benchmark
./run-all.sh master container master
```

Ensure `run-all.sh` exists and is executable.

### Docker stats

We can see docker stats by running the following command:

```bash
docker stats
```

## 🛑 Stopping the Cluster

```bash
docker-compose down
```

To clean up all volumes (removes results and shared SSH files):

```bash
docker-compose down -v
```

---

## 🛠️ Notes

- Ensure ports (like SSH) are not blocked by local firewalls.
- Use the fixed IPs or container names to connect between nodes.
- Check logs with:

  ```bash
  docker logs master
  docker logs node-01
  docker logs node-02
  ```

## ✅ Health Check

- The `master` container includes a health check to confirm that the SSH service is running:

  ```yaml
  healthcheck:
    test: ["CMD", "nc", "-z", "localhost", "22"]
    interval: 30s
    timeout: 10s
    retries: 3
  ```

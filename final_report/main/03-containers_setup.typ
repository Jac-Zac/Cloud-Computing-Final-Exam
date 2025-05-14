#import "@preview/hei-synd-report:0.1.1": *
#import "/metadata.typ": *
#pagebreak()

= Container Setup 

This project implements a lightweight HPC-like environment using Docker containers to simulate ... . The architecture cosnists of one *master* and two *worker nodes*. Communication between nodes is enabled by SSH, and MPI (Message Passing Interface) benchmarks are executed using a shared volume and predefined IP addresses.

Overall, the system design should replicate an HPC cluster's core features in a containerised environment. 

The deployment consists of a master node, responsible of directing tasks and starting SSH communication; two worker nodes that execute master's direction on benchmark workloads; a shared volume which has the role of facilitating file sharing and finally predefined IP aliases to simplify communication between containers and hostfile management. 

This setup, which can be deployed through the use of Docker Compose, allows an automated execution of MPI benchmarks. 


== Project structure

The project's directory layout is as follows: 

```bash
.
├── Dockerfile              # Container image configuration
├── compose.yaml            # Multi-container orchestration
├── entrypoint.sh           # Initialization script
├── benchmark/              # Benchmark scripts and configurations
├── results/                # Output directories per node
│   ├── master/
│   ├── node-01/
│   └── node-02/
└── shared/                 # Docker-managed shared volume```

This modular structure allows for straightforward benchmarking, logging and scalability while also supporting separation concerns. 

== Getting started 
1. The first step to take is cloning the repository 

```bash
git clone <your-repo-url>
cd <repo-directory>
```

2. Make `entrypoint.sh` executable

```bash
chmod +x entrypoint.sh
```

3. Build and Start the Cluster through the use of Docker Compose

```bash
docker-compose -f compose.yaml up --build
```

The system builds automatically the images and starts three interconnected containers: the master node (`master`), which can ssh in other machines ad the two worker nodes (`node-01` and `node-02`). 

The master generates an SSH key and shares it with workers via a Docker-managed volume `hpc-shared`.

== SSH communication

// Not sure you want an infobox here
#infobox()[Following a similar structure to what has been done in VMS]

Upon startup: 
- The master node generates a root SSH keypair (if not already present).
- Worker nodes wait until the master's public key is available, then append it to their `authorized_keys`.
- Each container starts an SSH daemon, allowing for remote command execution.

== MPI Hostfile Generation

The `master` node creates an MPI-compatible hostfile at `/benchmark/configs/mpi-hostfile` with fixed IP aliases. This file defines the nodes and their allocated slot for parallel computation with the following format: 

  ```bash
  # Auto-generated MPI hostfile
  master slots=2
  node-01 slots=2
  node-02 slots=2
  ```

== Benchmarks execution

Once all containers are operational, benchmarks workloads can be executed from the master node:

```bash
docker exec -it master bash
cd /benchmark
./run-all.sh master container master
```

#infobox()[ 
  We can get stats on our containers by running:
  ```bash
  docker stats 
  ```
]

At this point it is important to ensure that the benchmark script `run-all.sh` exists and is executable.


== Stopping the Cluster

The system has two shutdown modes: 

1. Standard shutdown: stops the running containers but does not delete the volumes.

```bash
docker-compose down
```

2. Full cleanup: removes containers and cleans up all volumes (removes results and shared SSH files):

```bash
docker-compose down -v
```

// want to put it as an infobox?

== Considerations

There are several considerations to address in the system design:

- Ensure ports (like SSH) are not blocked by local firewalls.
- Use the fixed IPs or container names to connect between nodes.
- Check logs with:

  ```bash
  docker logs master
  docker logs node-01
  docker logs node-02
  ```

== Health Check

- To verify service availability, the `master` container includes a health check to confirm that the SSH service is running:

  ```yaml
  healthcheck:
    test: ["CMD", "nc", "-z", "localhost", "22"]
    interval: 30s
    timeout: 10s
    retries: 3
  ```

#import "@preview/hei-synd-report:0.1.1": *
#import "/metadata.typ": *

= Container Setup 

This section focuses on implementing a similar setup to what we have previously done using Virtual Machines but with containers. In this case the container engine used is Docker. The architecture similarly to before; consists of one *master* and two *worker nodes*. Communication between nodes is enabled by SSH, and MPI (Message Passing Interface) benchmarks are executed using a shared volume and predefined IP addresses.

The deployment consists of a master node and two worker nodes that execute master's direction on benchmark workloads together with the master. Moreover a shared volume which has the role of facilitating file sharing and finally predefined IP aliases to simplify communication between containers.

This setup, which can be deployed through the use of Docker Compose, allows an automated execution of MPI benchmarks. 

== Project structure

The project's directory layout is as follows: 

```bash
.
├── Dockerfile              # Container image configuration
├── compose.yaml            # Multi-container orchestration
├── entrypoint.sh           # Initialization script
└── Performance_Testing/    # A directory with the tests to perform
```

This modular structure allows for straightforward benchmarking, logging and scalability while also supporting separation concerns. 

== Getting started 
1. Make `entrypoint.sh` executable

```bash
chmod +x entrypoint.sh
```

2. Build and Start the Cluster through the use of Docker Compose


#infobox()[
Each node has a limit of 2 CPU cores. However, core pinning for Docker containers using the `--cpuset-cpus` option is not very effective considering the virtualisation layer in between.
]

```bash
docker-compose -f compose.yaml up --build
```

The system builds automatically the images and starts three interconnected containers: the master node (`master`), which can ssh in other machines ad the two worker nodes (`node-01` and `node-02`). 

The master generates an SSH key and shares it with workers via a Docker-managed volume `hpc-shared`.

== SSH communication

// Not sure you want an infobox here
#infobox()[Following a similar structure to what has been done in VMS]

*Upon startup:*

- The master node generates a root SSH keypair (if not already present).
- Worker nodes wait until the master's public key is available, then append it to their `authorized_keys`.
- Each container starts an SSH daemon, allowing for remote command execution.

== Benchmarks execution

Once all containers are operational, benchmarks workloads can be executed from the master node:

```bash
docker exec -it master bash
cd /shared/Performance_Testing
./run-all.sh /config/mpi-hostfile
```

#infobox()[
  When running scripts with mpi if you haven't configured another user you might need to export the following flags in your shell:

  ```bash
  OMPI_ALLOW_RUN_AS_ROOT=1
  OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
  ```

  You can do so directly or put them inside your `.bashrc`/`.zshrc`.
]

#ideabox()[
  We can get stats on our containers by running: `docker stats `
]

At this point it is important to ensure that the benchmark script `run-all.sh` exists and is executable.


#infobox()[
The system has two shutdown modes: 

1. Standard shutdown: stops the running containers but does not delete the volumes.

```bash
docker-compose down
```

2. Full cleanup: removes containers and cleans up all volumes (removes results and shared SSH files):

```bash
docker-compose down -v
```
]

=== Considerations

There are several considerations to address in the system design:

- Ensure ports (like SSH) are not blocked by local firewalls.
- Use the fixed IPs or container names to connect between nodes.
- Check logs with:

  ```bash
  docker logs master
  docker logs node-01
  docker logs node-02
  ```

=== Health Check

- To verify service availability, the `master` container includes a health check to confirm that the SSH service is running:

  ```yaml
  healthcheck:
    test: ["CMD", "nc", "-z", "localhost", "22"]
    interval: 30s
    timeout: 10s
    retries: 3
  ```

And all the worker nodes specified this in their configuration:

```bash
depends_on:
  - master
```

This makes nodes services depends on the service named master.
Thus instructing Docker Compose to start the master service before starting the dependent service.
Therefore controlling the startup order of containers within the same `compose` file. 

From the Github repo also the #link("https://github.com/Jac-Zac/Cloud-Computing-Final-Exam/blob/main/Containers/compose.yaml")[compose] file and the #link("https://github.com/Jac-Zac/Cloud-Computing-Final-Exam/blob/main/Containers/Dockerfile")[Dockerfile] are also accessible.

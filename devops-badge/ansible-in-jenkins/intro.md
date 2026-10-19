# Ansible Integration in Jenkins

Your team's web servers are set up by hand. You're asked to automate it: a
Jenkins job hands the Ansible work to a dedicated **Ansible control node**, and
Ansible on that node installs Docker and Docker Compose on every web server.
Jenkins itself must not run Ansible.

This lab has no AWS account, so it uses stand-ins for the cloud parts:

| In production | In this lab |
|---|---|
| Jenkins server | Jenkins in a Docker container named `jenkins` ([open Jenkins]({{TRAFFIC_HOST1_8080}})), user `admin` / password `admin` |
| Ansible control node (a droplet you SSH into as `root`) | Container `ansible-server` (Ubuntu 24.04, host name `ansible-server` from Jenkins, SSH as `root` by key). Python 3.12 from apt is there; Ansible is not. There is no `pip`, and the system Python is "externally managed" (PEP 668), so Python libraries come from apt packages (`python3-<name>`), not `pip install`. The Docker API of this machine is reachable from it at `/var/run/docker.sock` |
| EC2 instances, tagged by role | Containers on the Docker network `lab`, running Amazon Linux 2023 with SSH. They publish no ports: they are reachable only on their own IP address on the `lab` network, port 22. Log in as `ec2-user` (passwordless `sudo`). Each has a Docker label `role`: the web servers are `role=webserver` |
| `aws_ec2` dynamic inventory plugin (EC2 API, needs `boto3`) | `community.docker.docker_containers` inventory plugin (Docker API, needs the Python package `requests`, apt `python3-requests`). Docker labels play the part of EC2 tags. Like `aws_ec2`, the plugin only reads inventory files whose names end in `docker.yml` or `docker.yaml`, and it returns container labels and network details only with `verbose_output: true` |
| Jenkins credentials for the droplet and the EC2 key pair | Already created: `ansible-server-key` (user `root`) and `ec2-server-key` (user `ec2-user`) |

The servers are containers without systemd, so services can't be started there:
installing the packages is enough, the Docker daemon does not need to run.

The app's code is in `/root/java-maven-app` (a git repo, branch `master`). A
pipeline job called `java-maven-app` already exists in Jenkins and builds the
`Jenkinsfile` from the `master` branch of that repo, so Jenkins only sees what
you **commit**.

Setup takes a few minutes. Wait for the terminal to say the lab is ready, then
click **START**.

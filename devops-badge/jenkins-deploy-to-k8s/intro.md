# Deploy to Kubernetes From a Jenkins Pipeline

Your team builds and deploys `java-maven-app` by hand. You're asked to put it on a
proper CI/CD pipeline: every run of the Jenkins job builds the app, packages it
as an image, publishes it, and rolls it out to the cluster.

[Open Jenkins]({{TRAFFIC_HOST1_8080}}) (user `admin`, password `admin`).

This lab has no AWS account, so it uses stand-ins for the AWS parts:

| In production | In this lab |
|---|---|
| EKS cluster | A Kubernetes cluster on this machine (k3s). API server `https://127.0.0.1:6443`, admin kubeconfig `/etc/rancher/k3s/k3s.yaml` |
| ECR | A private registry at `localhost:5000` (plain HTTP, no login needed) |
| Jenkins server | Jenkins in a Docker container named `jenkins`, user `admin` / password `admin`. It uses the host's network, so `localhost:5000` and `127.0.0.1:6443` work from inside it too. It runs as root with the host's Docker socket; Maven (tool name `Maven`) and the docker CLI are installed. Its home is `/var/jenkins_home` (on the host: `/var/lib/jenkins-lab`) |
| GitLab repo | The local git repo `/root/java-maven-app`, branch `master`. Jenkins reads it read-only (as `file:///host-root/java-maven-app`) and cannot push back to it |

A pipeline job called `java-maven-app` already exists in Jenkins and builds the
`Jenkinsfile` from the `master` branch of that repo, so Jenkins only sees what
you **commit**.

Setup takes a few minutes. Wait for the terminal to say the lab is ready, then
click **START**.

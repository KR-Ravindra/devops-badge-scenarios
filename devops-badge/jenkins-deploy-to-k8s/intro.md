# Deploy to Kubernetes From a Jenkins Pipeline

Your team builds and deploys `java-maven-app` by hand. You're asked to put it on a
proper CI/CD pipeline: every run of the Jenkins job builds the app, packages it
as an image, publishes it, and rolls it out to the cluster.

This lab has no AWS account, so it uses stand-ins for the AWS parts:

| In production | In this lab |
|---|---|
| EKS cluster | A Kubernetes cluster on this machine (k3s). Admin kubeconfig: `/etc/rancher/k3s/k3s.yaml` |
| ECR | A private registry at `localhost:5000` (no login needed) |
| Jenkins server | Jenkins in a Docker container named `jenkins`, user `admin` / password `admin` |

The app's code is in `/root/java-maven-app` (a git repo, branch `master`). A
pipeline job called `java-maven-app` already exists in Jenkins and builds the
`Jenkinsfile` from the `master` branch of that repo, so Jenkins only sees what
you **commit**.

Setup takes a few minutes. Wait for the terminal to say the lab is ready, then
click **START**.

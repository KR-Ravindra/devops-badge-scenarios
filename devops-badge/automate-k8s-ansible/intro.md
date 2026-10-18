# Automate Kubernetes Deployment With Ansible

Your team has a Kubernetes cluster that Terraform provisioned, and they deploy
applications into it by hand. You're asked to automate that with Ansible, so a
single playbook run sets up the application's namespace and deploys it.

This lab has no AWS account, so it uses stand-ins for the AWS parts:

| In production | In this lab |
|---|---|
| EKS cluster provisioned with Terraform | A Kubernetes cluster on this machine (k3s), already running |
| Kubeconfig written by the Terraform EKS module | `/root/kubeconfig_myapp-eks-cluster` |
| Ansible control node | This machine: Ansible and the `kubernetes.core` collection are installed |

Your project is in `/root/ansible-k8s` (a git repo, branch `main`). It already
holds the application's Kubernetes manifest, `nginx-config.yaml`.

Setup takes a few minutes. Wait for the terminal to say the lab is ready, then
click **START**.

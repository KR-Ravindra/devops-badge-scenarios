# Automate Kubernetes Deployment With Ansible

Your team has a Kubernetes cluster that Terraform provisioned, and they deploy
applications into it by hand. You're asked to automate that with Ansible, so a
single playbook run sets up the application's namespace and deploys it.

This lab has no AWS account, so it uses stand-ins for the AWS parts:

| In production | In this lab |
|---|---|
| EKS cluster provisioned with Terraform | A Kubernetes cluster on this machine (k3s), already running |
| Kubeconfig written by the Terraform EKS module | `/root/kubeconfig_myapp-eks-cluster` |
| AWS load balancer for a `LoadBalancer` Service | The cluster's built-in ServiceLB, which publishes the Service on this machine's port 80 |
| Ansible control node | This machine: Ansible and the `kubernetes.core` collection are installed |

Ansible on this machine is installed in a Python virtualenv at `/opt/ansible`:
`ansible-playbook` and the other `ansible*` commands run on
`/opt/ansible/bin/python3`, and that is also the Python Ansible uses for tasks on
`localhost` (the project's `ansible.cfg` sets `interpreter_python` to it). The
system `/usr/bin/python3` is not used by Ansible.

Your project is in `/root/ansible-k8s` (a git repo, branch `main`). It already
holds the application's Kubernetes manifest, `nginx-config.yaml`.

Setup takes a few minutes. Wait for the terminal to say the lab is ready, then
click **START**.

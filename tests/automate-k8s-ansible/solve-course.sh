#!/bin/bash
# Course-faithful solution (15-ansible "Automate Kubernetes Deployment"): install
# the `openshift` python module (pulls in `kubernetes`) for Ansible's Python, then
# the course's deploy-to-k8s.yaml with the kubeconfig attribute added per task and
# the manifest path adapted to this lab. Course: `pip3 install openshift --user`;
# here Ansible's Python is the /opt/ansible venv, where --user is not allowed.
set -euo pipefail
cd /root/ansible-k8s

/opt/ansible/bin/pip3 install -q --disable-pip-version-check openshift==0.13.2

cat > deploy-to-k8s.yaml <<'PB'
---
- name: Deploy app in new namespace
  hosts: localhost
  tasks:
    - name: Create a k8s namespace
      kubernetes.core.k8s:
        name: my-app
        api_version: v1
        kind: Namespace
        state: present
        kubeconfig: ~/kubeconfig_myapp-eks-cluster
    - name: Deploy nginx app
      kubernetes.core.k8s:
        src: ~/ansible-k8s/nginx-config.yaml
        state: present
        kubeconfig: ~/kubeconfig_myapp-eks-cluster
        namespace: my-app
PB

ansible-playbook deploy-to-k8s.yaml
kubectl -n my-app rollout status deploy/nginx --timeout=180s

git add deploy-to-k8s.yaml
git commit -qm "Deploy nginx to my-app with Ansible"

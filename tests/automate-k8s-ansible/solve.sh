#!/bin/bash
# Reference solution: install the python kubernetes client into Ansible's own
# interpreter, write the course playbook with an explicit kubeconfig, run it
# twice (second run must be changed=0) and commit.
set -euo pipefail
cd /root/ansible-k8s

# the trap: kubernetes.core needs the `kubernetes` library in the Python Ansible runs on
ansible-playbook --version | grep 'python version'
/opt/ansible/bin/pip install -q --disable-pip-version-check kubernetes==36.0.3

cat > deploy-to-k8s.yaml <<'PB'
---
- name: Deploy app in new namespace
  hosts: localhost
  gather_facts: false
  vars:
    kubeconfig: /root/kubeconfig_myapp-eks-cluster
  tasks:
    - name: Create a k8s namespace
      kubernetes.core.k8s:
        kubeconfig: "{{ kubeconfig }}"
        name: my-app
        api_version: v1
        kind: Namespace
        state: present
    - name: Deploy nginx app
      kubernetes.core.k8s:
        kubeconfig: "{{ kubeconfig }}"
        src: "{{ playbook_dir }}/nginx-config.yaml"
        state: present
        namespace: my-app
        wait: true
PB

env -u KUBECONFIG ansible-playbook deploy-to-k8s.yaml
env -u KUBECONFIG ansible-playbook deploy-to-k8s.yaml | tee /tmp/second-run
grep -Eq 'changed=0 .*failed=0' /tmp/second-run

git add deploy-to-k8s.yaml
git commit -qm "Deploy nginx to my-app with Ansible"

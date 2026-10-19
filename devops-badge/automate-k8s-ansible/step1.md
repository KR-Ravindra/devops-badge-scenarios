# Deploy to the cluster with an Ansible playbook

Write an Ansible playbook `/root/ansible-k8s/deploy-to-k8s.yaml` that, using the
`kubernetes.core` collection against the cluster in
`/root/kubeconfig_myapp-eks-cluster`:

1. creates the namespace `my-app`,
2. deploys the application from `nginx-config.yaml` (Deployment `nginx` and
   Service `nginx`) into that namespace.

Run the playbook to deploy the application. Everything in the cluster must be
created by your playbook, not by hand. Once it is up, the app is published on
this machine's port 80: [open the app]({{TRAFFIC_HOST1_80}}).

Requirements:

- The application must actually be up and answering over its Service.
- Running the playbook again must not change anything in the cluster.
- The playbook must work on its own: `check` runs
  `ansible-playbook deploy-to-k8s.yaml --check --diff` from `/root/ansible-k8s`
  in a fresh shell, without your shell's environment variables and without
  `-i`: hosts the playbook targets must be `localhost` or come from an inventory
  set in `/root/ansible-k8s/ansible.cfg`.
- Commit your playbook to the `main` branch.

> Run `check` any time to see your result. Click **Continue** to move on whenever you want — you can proceed even if it isn't passing yet.

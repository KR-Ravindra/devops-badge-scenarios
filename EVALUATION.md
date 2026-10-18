# DevOps Badge — Evaluation Guide

Eleven hands-on scenarios. Grading is a self-serve **`check`** command in each
environment (prints `✅ PASS` / `❌ NOT YET`) — it does **not** gate progress; the
candidate can always continue. So the badge decision is **yours to make by
observing** — run `check` yourself and watch *how* they solve it. For each scenario:

- **Auto-pass** = the objective bar `check` reports.
- **Weak / Solid / Strong** = what to look for while observing, for the badge score.

Suggested overall bar: **7/10 auto-passes**, with at least Solid on the two High
scenarios (`ha-hardening`, and the design follow-up on multi-region — see note).

| # | Scenario | Source Q | Skills | Difficulty | Time |
|---|----------|----------|--------|------------|------|
| 1 | `ingress-3-apps` | Q9 | Services, Ingress L7 vs L4 for non-HTTP | Medium | 15 min |
| 2 | `multi-env-helm` | Q4 | Helm values precedence, per-env config | Medium | 12 min |
| 3 | `debug-container-vm` | Q10 | Container/port troubleshooting on a VM | Low–Med | 10 min |
| 4 | `ha-hardening` | Q6 | HA: replicas, PDB, spread, probes | High | 20 min |
| 5 | `fix-crashloop` | — | Core k8s debugging (pod state/events) | Low–Med | 8 min |
| 6 | `shared-pipeline-library` | Q3 | DRY / shared pipeline design | Medium | 15 min |
| 7 | `private-registry` | Q7 | Artifact/registry management | Low–Med | 10 min |
| 8 | `dockerfile-multistage` | — | Multi-stage builds, image hygiene | Medium | 12 min |
| 9 | `configmap-secret-wiring` | — | ConfigMaps, Secrets, env injection | Low–Med | 10 min |
| 10 | `service-endpoints-debug` | — | Service selectors/endpoints debugging | Medium | 10 min |
| 11 | `jenkins-deploy-to-k8s` | Capstone 1 (M11 L06) | Jenkins pipeline: Maven → image → registry → k8s deploy | High | 40 min (+ ~5 min setup) |

> **Design-only questions (not simulated):** Q8 (multi-region AWS architecture) and
> the cluster-level tier of Q6 (multi-cluster/multi-AZ) don't fit a single-node lab.
> Keep those as whiteboard/verbal questions alongside this badge. Q1/Q2 were dropped
> (low signal per the review).

---

## 1. ingress-3-apps (Q9)
**Auto-pass:** web-a/web-b reachable by Host header through ingress; ftp-app reachable via an L4 Service (NodePort/LoadBalancer) on TCP 21.
- **Weak:** exposes all three with LoadBalancer/NodePort and never uses Ingress; or tries to put FTP behind the HTTP Ingress and can't explain why it fails.
- **Solid:** Services + Ingress for the web apps, an L4 Service for FTP.
- **Strong:** articulates that Ingress is L7/HTTP-only, names ingress-nginx TCP-services as the alternative, checks endpoints to debug.

## 2. multi-env-helm (Q4)
**Auto-pass:** `helm template` with each env file renders replicas 1/2/5 and image tags dev/staging/prod.
- **Weak:** copies the chart per env, or edits the template hardcoding values.
- **Solid:** overrides only via `values-<env>.yaml`.
- **Strong:** explains values precedence, mentions `--set`, `helm upgrade -f`, or a GitOps values-per-env layout; keeps one chart as source of truth.

## 3. debug-container-vm (Q10)
**Auto-pass:** `curl localhost:8080` returns 200.
- **Weak:** randomly recreates the container until it works, no diagnosis.
- **Solid:** reads `docker ps` PORTS, spots the 8080→8080 vs listen-on-80 mismatch, re-maps.
- **Strong:** verifies from inside the container first (`docker exec`), explains the layers (running ≠ mapped ≠ reachable).

## 4. ha-hardening (Q6) — High
**Auto-pass:** replicas ≥ 3, a PDB selecting the app, node spread (anti-affinity/topologySpread), a readinessProbe, ≥ 2 available.
- **Weak:** only bumps replicas.
- **Solid:** replicas + PDB + spread + probe all present and correct.
- **Strong:** explains PDBs cover *voluntary* disruption only, hard vs soft anti-affinity trade-offs on a small cluster, and names the cluster-level tier (multi-AZ/multi-cluster) as the next layer.

## 5. fix-crashloop
**Auto-pass:** `api` Deployment fully Ready.
- **Weak:** deletes/recreates without knowing why.
- **Solid:** uses `describe`/events, identifies ImagePullBackOff, fixes the tag.
- **Strong:** distinguishes image-pull vs crashloop vs bad-probe vs scheduling from the symptoms and says how each differs.

## 6. shared-pipeline-library (Q3)
**Auto-pass:** both builds still produce their artifacts, a shared file is sourced by both, packaging stage no longer duplicated inline.
- **Weak:** leaves duplication, or breaks one build.
- **Solid:** extracts a sourced library, parameterises by service name.
- **Strong:** relates it to Jenkins Shared Libraries / GH reusable workflows / GitLab `include`, discusses versioning the shared lib.

## 7. private-registry (Q7)
**Auto-pass:** registry answers on :5000 and `internal/app:1.0` is in the catalog.
- **Weak:** can't get push working, confuses local image list with registry contents.
- **Solid:** runs registry:2, tags, pushes, confirms via `_catalog`.
- **Strong:** connects to Nexus/Artifactory/Harbor/ECR, mentions auth, retention, and pull-through caching for apt/pypi/npm.

## 8. dockerfile-multistage
**Auto-pass:** image builds, serves `hello from app` on 8080, final image < 50 MB.
- **Weak:** can't get under the size limit, or breaks the runtime.
- **Solid:** multi-stage build, minimal final base, `CGO_ENABLED=0`.
- **Strong:** also covers layer caching/ordering, `.dockerignore`, pinned tags, non-root user.

## 9. configmap-secret-wiring
**Auto-pass:** ConfigMap `app-config` (APP_COLOR=blue) + Secret `app-secret` (API_KEY=s3cr3t) created and injected; pod env matches; sourced via valueFrom/envFrom, not hardcoded.
- **Weak:** hardcodes env values in the pod spec.
- **Solid:** proper ConfigMap + Secret + valueFrom wiring.
- **Strong:** notes Secrets are base64 not encrypted-at-rest by default, files-vs-env, external secret stores.

## 10. service-endpoints-debug
**Auto-pass:** Service `orders` has ≥ 1 endpoint and targetPort 8080.
- **Weak:** deletes/recreates the Service or the pods blindly.
- **Solid:** compares selector to pod labels, fixes the selector, confirms endpoints.
- **Strong:** checks `get endpoints` first; separates selector mismatch from targetPort mismatch from unhealthy pods.

## 11. jenkins-deploy-to-k8s (Capstone 1, DevOps M11 L06 "Deploy to EKS from Jenkins")
Stand-ins: k3s for EKS, `registry:2` on :5000 for ECR, plain kubeconfig instead of AWS keys + `aws-iam-authenticator`. Jenkins is pre-installed with Maven and the docker CLI but **no kubectl and no cluster access**; the job `java-maven-app` exists and reads the Jenkinsfile from the committed `master` of `/root/java-maven-app`.
**Auto-pass:** latest build green; the tag it pushed is in the registry, isn't `latest`, and is the image the `prod/java-maven-app` Deployment runs; rollout complete; Service `java-maven-app:8080` returns HTTP 200.
**Built-in trap (from the course repo as-is):** the Dockerfile `ENTRYPOINT` hardcodes `java-maven-app-1.0-SNAPSHOT.jar` while `pom.xml` is `1.1.0-SNAPSHOT`, so the first deploy crash-loops. A candidate who only reads the green build will miss it.
- **Weak:** edits files without committing and wonders why Jenkins doesn't see them; deploys by hand with kubectl outside Jenkins; uses `:latest`; copies the admin kubeconfig into the repo or the Jenkinsfile.
- **Solid:** installs kubectl in the Jenkins container, gives Jenkins the kubeconfig (credential or `jenkins_home/.kube`), build → push → apply with a unique tag (`BUILD_NUMBER` or app version), finds and fixes the jar-name crash from `kubectl logs`.
- **Strong:** stores the kubeconfig as a Jenkins credential (`withCredentials` file / `withKubeConfig`), and uses a ServiceAccount scoped to `prod` instead of cluster-admin; waits on `rollout status` so a crash fails the build; explains what changes on real EKS (aws-iam-authenticator / `aws eks update-kubeconfig`, aws-auth/access entries, ECR login with `aws ecr get-login-password`).
- **Ask in the interview:** "In EKS, how does Jenkins authenticate to the cluster, and what IAM permissions does that identity need?" (the part the lab can't test).
Reference solution: `tests/jenkins-deploy-to-k8s/solve.sh` (CI runs setup → check fails → solve → check passes).

## 12. microservices-helm (Capstone 4, DevOps M10 "Deploy Microservices with Helm")
Starts from Online Boutique v0.10.4 as one plain `config.yaml` (11 Deployments + Services, no probes, resources, replicas or securityContext; `redis:alpine` unpinned). k3s single node with servicelb; helm, helm-diff and helmfile pre-installed; images pre-pulled.
**Auto-pass:** all 11 Deployments in `microservices` carry a Helm release annotation; the 10 app services come from ONE chart; every release is declared in `/root/online-boutique/helmfile.yaml` (`helmfile list` works); every container has a version-pinned image, liveness + readiness probes, CPU/memory requests + limits; app services ≥2 replicas, redis 1; all available; and a scripted customer journey passes (storefront → product page → add to cart → checkout "Your order is complete"), which exercises all 11 services.
**Built-in traps:** `redis:alpine` is a floating tag (must be pinned); the single node can't fit upstream-sized requests ×2 replicas, so the candidate has to read `kubectl describe node` and size requests, or watch pods sit Pending; emailservice's Service port (5000) differs from its container port (8080); the frontend needs `SHOPPING_ASSISTANT_SERVICE_ADDR` set even though that service doesn't exist.
- **Weak:** 11 near-identical charts (copy-paste) or one chart with all services hardcoded; `kubectl apply` outside Helm; leaves `redis:alpine`; probes on the wrong port; requests copied from upstream, so half the pods stay Pending; runs 2 redis replicas on separate emptyDirs (carts diverge).
- **Solid:** one generic `microservice` chart driven by per-service values files, a small redis chart, `helmfile sync` deploys everything; gRPC probes on the gRPC services and `httpGet /_healthz` on the frontend; requests sized to the node.
- **Strong:** `helmDefaults: wait`, so a broken release fails the sync; securityContext (runAsNonRoot, readOnlyRootFilesystem, drop ALL) via values; PodDisruptionBudgets or topology spread; explains why redis stays at 1 replica (or uses a StatefulSet + PVC) and how they'd promote dev → prod with helmfile environments.
- **Ask in the interview:** "What happens to customer carts when the redis pod restarts here, and how would you fix that in production?"
Reference solution: `tests/microservices-helm/solve.sh` (CI runs setup → check fails → solve → check passes).

## 13. automate-k8s-ansible (Capstone 2, DevOps M15 "Automate Kubernetes Deployment")
Starts from the course project `15-ansible/ansible-projects` @ `3519713` with the playbook removed: only `nginx-config.yaml` (nginx Deployment + LoadBalancer Service, image pinned to `nginx:1.29.8`) in `/root/ansible-k8s`. Stand-ins: k3s for EKS; the Terraform EKS step is replaced by a ready cluster whose kubeconfig sits at `/root/kubeconfig_myapp-eks-cluster` (where the Terraform EKS module writes it). ansible-core 2.19.13 (venv `/opt/ansible`) + kubernetes.core 6.5.0 are installed; the python `kubernetes` client is not.
**Auto-pass:** `deploy-to-k8s.yaml` is committed; `my-app` namespace, Deployment and Service `nginx` exist, rollout complete, Service returns HTTP 200; neither object has a `kubectl*` field manager (created through the python client); `ansible-playbook deploy-to-k8s.yaml --check --diff` run by `check` from a clean environment (no `KUBECONFIG`) succeeds, its `kubernetes.core.k8s` tasks cover the Namespace, Deployment and Service, no shell/command tasks, and every task reports changed=0 (idempotent and matching the live cluster). Deleting the Deployment, recreating it with kubectl, or scaling it by hand all turn the result back to NOT YET; re-running the playbook restores PASS.
**Built-in traps:** (1) "Failed to import the required Python library (kubernetes)": the library must go into the Python Ansible actually uses (`/opt/ansible`), not system pip (which Ubuntu 24.04 also blocks as externally-managed); (2) the kubeconfig isn't at `~/.kube/config` and `kubectl` works anyway (k3s default), so the playbook needs `kubeconfig:` / `K8S_AUTH_KUBECONFIG` rather than a shell export that `check`'s clean environment won't have; (3) the course playbook's `src: ~/demo-projects/K8s-Files/nginx-config.yaml` path doesn't exist here.
- **Weak:** `kubectl apply` by hand or via `shell:`/`command:` tasks; `pip3 install kubernetes` system-wide and stuck on why Ansible still can't import it; relies on an exported `KUBECONFIG` in their own shell; leaves the playbook uncommitted.
- **Solid:** reads the interpreter path from the error and installs `kubernetes` into Ansible's venv (or sets `ansible_python_interpreter` to a Python that has it); `kubernetes.core.k8s` for the namespace and `src:` (relative to `playbook_dir`) for the manifest with an explicit `kubeconfig`; shows a second run reports changed=0.
- **Strong:** `wait: true` (or a `k8s_info` wait) so the play fails if the rollout fails; pins the library in a `requirements.txt` / `requirements.yml` (collections) for reproducibility; keeps the kubeconfig path in vars/inventory; uses `--check --diff` before applying; explains how on real EKS the kubeconfig authenticates (`aws eks get-token` exec plugin, IAM identity mapped via access entries/aws-auth) and why the Ansible control node needs AWS credentials too.
- **Ask in the interview:** "Terraform created the EKS cluster: how does your Ansible playbook get a working kubeconfig and credentials for it, and what happens to the playbook's idempotency if someone changes the Deployment with kubectl?" (the Terraform/EKS part the lab can't test).
Reference solution: `tests/automate-k8s-ansible/solve.sh` (CI runs setup → check fails → trap verified → solve → check passes → delete / kubectl-apply / manual scale each fail → playbook re-run restores PASS).

## 14. terraform-cicd (Capstone 3, DevOps M12 "Complete CI/CD with Terraform")
Stand-ins: a `lab-server:1.0` container created by Terraform's `kreuzwerker/docker` provider for EC2 (sshd, user `ec2-user`, public key injected at creation like `key_name`, drives the host Docker engine), MinIO bucket `tf-state` for the S3 state bucket, `registry:2` on :5000 for Docker Hub/ECR, MinIO keys as the AWS keys (Jenkins secret text `jenkins_aws_access_key_id` / `jenkins-aws_secret_access_key`). Jenkins (:8081) has Maven, docker CLI, terraform and ssh-agent; SSH credential `server-ssh-key` (ec2-user) is pre-created; public key at `/root/.ssh/server-key.pub`. Job `java-maven-app` reads the Jenkinsfile from committed `master` of `/root/java-maven-app`, which has the course compose file + `server-cmds.sh` and a starter `terraform/` (no backend).
**Auto-pass:** latest build green; the `tf-state` bucket holds a Terraform state with the server (`docker_container`) and that container is running from `lab-server:1.0`; the build log addressed the server's IP from the state; a compose-started container (working dir `/home/ec2-user`) runs `localhost:5000/java-maven-app:<tag>`, the tag isn't `latest`, is in the registry and was pushed by the latest build; `:8080` returns HTTP 200.
**Built-in traps:** starter Terraform keeps state local (no backend) and reads the public key from a hardcoded laptop path (`/home/nana/.ssh/id_rsa.pub`) that doesn't exist in Jenkins; the course `server-cmds.sh` expects Docker Hub user/password arguments and `docker login`s to Docker Hub, and the compose file needs `IMAGE` set; the course Jenkinsfile's fixed `sleep 90` and hardcoded image name.
- **Weak:** leaves state local (or copies a tfstate around); hardcodes the server IP; runs `terraform apply` or `docker-compose` by hand outside Jenkins; uses `:latest`; pastes the private key or MinIO keys into the repo.
- **Solid:** S3 backend with endpoint override (`endpoints.s3`, `use_path_style`, `skip_*`), credentials via `credentials()` env, `terraform output -raw` captured into a variable, `sshagent` + `scp`/`ssh` with the image passed to `server-cmds.sh`, unique tag per build, fixes the public-key path (tfvars, `TF_VAR_`, or a credential).
- **Strong:** passes the public key as a variable from a Jenkins credential instead of committing it; replaces the fixed sleep with an SSH readiness retry; adds `-input=false`/`TF_IN_AUTOMATION`; explains state locking (DynamoDB / `use_lockfile`), why remote state matters for a CI agent, and that the pipeline is idempotent (second run = no-op apply, recreate on drift).
- **Ask in the interview:** "Two pipeline runs start at the same time against this state: what goes wrong, and how does the S3 backend prevent it on AWS? And how would you tear the test server down after the deploy is verified?"
Reference solution: `tests/terraform-cicd/solve.sh` + `tests/terraform-cicd/build.sh` (CI runs setup → check fails → starter build fails → solve → check passes → app removed fails → rebuild passes → state deleted fails).

## 15. ansible-in-jenkins (Capstone 5, DevOps M15 "Ansible Integration in Jenkins")
Stand-ins: containers on Docker network `lab` for the droplet and the EC2 instances (`ansible-server`: Ubuntu, sshd as root, python3, no Ansible, host Docker socket mounted; `ec2-1`/`ec2-2`: Amazon Linux 2023, sshd, `ec2-user` + passwordless sudo, label `role=webserver`; decoy `ec2-db` with `role=database`), and the `community.docker.docker_containers` inventory plugin (Docker API, labels) for `aws_ec2` (EC2 API, tags). Jenkins (admin/admin) has ssh-agent + ssh-steps, the credentials `ansible-server-key` and `ec2-server-key`, no Docker socket, and the job `java-maven-app` reading the Jenkinsfile from the committed `master` of `/root/java-maven-app` (course `feature/ansible` code with the Jenkinsfile, prepare script and ansible/ folder removed).
**Auto-pass:** latest build green; Ansible installed on `ansible-server` and absent from the Jenkins container; during that build Jenkins logged in to ansible-server over SSH as root; the console has a PLAY RECAP with every `role=webserver` host at unreachable=0/failed=0 and no line for jenkins/ansible-server/ec2-db; each web server has an `ec2-user` SSH login from ansible-server and no `docker exec`/API session during the build; for `ec2-user`, `docker --version` and `docker compose version` work and the user is in the `docker` group; ec2-db untouched. Once ec2-1/ec2-2 pass, `check` launches `ec2-3` (role=webserver) and requires an unchanged re-run that configures it too.
**Built-in traps:** the plugin defaults to the docker-api connection (graded as not SSH); `connection_type: ssh` alone resolves to the published port/127.0.0.1, so the candidate must compose the `lab` network IP; inventory filename must end in `docker.yml/yaml`; without a label filter the inventory includes Jenkins, the control node and the database decoy; the course's `systemd: started` task fails (no systemd); the course prepare script's `apt install python3-boto3` lacks `-y`; the copied key needs mode 600; uncommitted files are invisible to Jenkins; the scale-out defeats static host lists.
- **Weak:** installs Ansible in the Jenkins container or runs ansible-playbook by hand on ansible-server; static inventory of IPs/names (fails on ec2-3); `hosts: all` with no filter (configures Jenkins/ec2-db); lets the plugin use docker exec; hard-codes keys into the repo.
- **Solid:** the course flow: `sshagent` + scp of ansible files and the `ec2-server-key` file, `sshScript` prepare (ansible + Docker SDK/requests), `sshCommand ansible-playbook`; dynamic inventory with keyed_groups or filters on the role label and composed `ansible_host`; dnf docker + user in docker group + compose plugin.
- **Strong:** idempotent playbook (second run changed=0 on configured hosts), pins the Compose version instead of `latest`, keeps `StrictHostKeyChecking`/`host_key_checking` deliberate rather than blanket-off and can explain the trade-off, cleans the key off the control node afterwards, explains why the work runs on a separate control node (credentials, blast radius, Jenkins agent hygiene).
- **Ask in the interview:** "On AWS, how does the control node get permission to call the EC2 API for the aws_ec2 inventory, and how would you avoid copying the EC2 private key around?" (IAM instance profile vs keys, SSM/EC2 Instance Connect: the part the lab can't test).
Reference solution: `tests/ansible-in-jenkins/solve.sh` (CI runs setup → check fails → solve → check launches ec2-3 → `solve.sh rerun` → check passes, plus a self-test that the grader sees `docker exec`).

## 16. website-monitoring (Capstone 6, DevOps M14 "Automation with Python: Website Monitoring and Recovery")
Stand-ins: container `web-server` (192.168.77.10, sshd + nginx front on :8080 + docker CLI) for the Linode server, the app container `nginx-app` behind it, a Linode API v4 compatible mock on `localhost:8000/v4` (instance `61420077`, Bearer token; a frozen server still reports `running`; reboot stops the app container like a real reboot does), Mailpit for Gmail SMTP (`localhost:1025`, login required, inbox viewer on :8025). Token and mail password are random per lab and handed over in `/root/cloud-credentials.txt`. requests, paramiko, schedule and linode_api4 are pre-installed; `/root/monitoring` starts empty.
**Auto-pass:** no literal token/password in any `.py` under `/root/monitoring`; a `monitor.py` process is running; stage 1 (grader stops `nginx-app`, site returns 5xx): within 75s an alert reaches `ops@lab.local`, `nginx-app` is started again by a docker command run on the server, HTTP 200, and no reboot was requested; stage 2 (grader freezes `web-server`, SSH and HTTP hang): within 150s an alert arrives, an authenticated reboot hits the API, server and app are back and the site returns 200. The grader restores the lab on any failure.
**Built-in traps:** `requests.get` without a timeout hangs forever on a frozen server (stage 2 never alerts), and so does a `requests.get` outside the try; the API says `running` for the hung server, so "reboot only if status != running" never fires; the reboot leaves the app container stopped, so the script must restart it afterwards; SMTP rejects unauthenticated mail; hardcoded secrets fail.
- **Weak:** hardcodes the token/password; runs the script in the foreground and it dies with the terminal; no timeouts, so the monitor hangs; reboots the server for every failure; restarts the container with host-side `docker` instead of over SSH; one exception kills the whole loop.
- **Solid:** course structure (`schedule` + `requests` + `smtplib` + `paramiko` + `linode_api4`) with env-var credentials, timeouts on HTTP/SMTP/SSH, separate paths for non-200 (restart container) and connection error (reboot, poll status until `running`, then restart container), started as a systemd service or under nohup/tmux.
- **Strong:** systemd unit with `EnvironmentFile` and `Restart=always`; bounded polling and retries for SSH after reboot; a top-level try/except so the scheduler survives a failed recovery; avoids alert storms (backoff or "recovered" mail); uses the provider's status as a signal, not as the truth; can explain why AutoAddPolicy is a MITM risk and how to pin the host key.
- **Ask in the interview:** "Your monitor runs on the same server it watches, or the server is fine but the monitor host loses network. What happens, and where should this monitor really run?"
Reference solution: `tests/website-monitoring/solve.sh` (CI runs setup → check fails → hardcoded token fails → solve → check passes → removing the requests timeout fails stage 2 and the lab is restored).

#!/bin/bash
# Seeds: k3s (EKS stand-in) with its kubeconfig copied to where the Terraform EKS
# module would write it, ansible-core in a venv + the kubernetes.core collection
# (but NOT the python `kubernetes` library the collection needs), and a starter
# repo with the course's nginx manifest. Installs `check`.
exec >>/var/log/badge-setup.log 2>&1
set -x
trap 'touch /tmp/setup-failed' ERR
set -eE

K3S_VERSION=v1.34.11+k3s1
ANSIBLE_CORE_VERSION=2.19.13
K8S_CORE_VERSION=6.5.0
NGINX_IMAGE=docker.io/library/nginx:1.29.8
# course: twn-devops-bootcamp/latest/15-ansible/ansible-projects @ main
COURSE_REPO=https://gitlab.com/twn-devops-bootcamp/latest/15-ansible/ansible-projects.git
COURSE_SHA=351971311383b72db5c89891770a032aa5c3b0da
KCFG=/root/kubeconfig_myapp-eks-cluster
REPO=/root/ansible-k8s

export DEBIAN_FRONTEND=noninteractive

# --- k3s (EKS stand-in). No KUBECONFIG in the shell on purpose: the cluster's
# kubeconfig is a separate file, like the one Terraform writes for EKS. ---
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" sh -
for i in $(seq 1 60); do k3s kubectl get nodes 2>/dev/null | grep -q ' Ready' && break; sleep 3; done
cp /etc/rancher/k3s/k3s.yaml "$KCFG"
chmod 600 "$KCFG"
k3s ctr images pull "$NGINX_IMAGE" >/dev/null &

# --- Ansible: ansible-core in a venv + kubernetes.core, without the python
# `kubernetes` client the collection imports (the course's first error) ---
command -v git >/dev/null || { apt-get update -qq; apt-get install -y -qq git; }
python3 -m venv /opt/ansible 2>/dev/null || { apt-get update -qq; apt-get install -y -qq python3-venv; rm -rf /opt/ansible; python3 -m venv /opt/ansible; }
/opt/ansible/bin/pip install -q --disable-pip-version-check "ansible-core==$ANSIBLE_CORE_VERSION"
for b in ansible ansible-playbook ansible-galaxy ansible-doc ansible-config ansible-inventory; do
  ln -sf /opt/ansible/bin/$b /usr/local/bin/$b
done
mkdir -p /usr/share/ansible/collections
ansible-galaxy collection install -p /usr/share/ansible/collections "kubernetes.core:==$K8S_CORE_VERSION"
/opt/ansible/bin/pip uninstall -y -q kubernetes 2>/dev/null || true

# --- starter repo: the course project's nginx manifest, without the playbook ---
rm -rf "$REPO" /tmp/course-src
git clone -q "$COURSE_REPO" /tmp/course-src
git -C /tmp/course-src checkout -q "$COURSE_SHA"
mkdir -p "$REPO"
# pin the floating `nginx` image of the course manifest to a pre-pulled version
sed "s#image: nginx\$#image: nginx:${NGINX_IMAGE##*:}#" /tmp/course-src/nginx-config.yaml > "$REPO/nginx-config.yaml"
grep -q "image: nginx:${NGINX_IMAGE##*:}" "$REPO/nginx-config.yaml"
printf '[defaults]\nhost_key_checking = False\n' > "$REPO/ansible.cfg"
rm -rf /tmp/course-src
cd "$REPO"
git init -q -b main
git config user.email "you@example.com"; git config user.name "You"
git add -A && git commit -qm "nginx manifest"
cd /

# --- grader's audit callback: records which k8s objects each task touched ---
mkdir -p /opt/badge/callback
cat > /opt/badge/callback/badge_audit.py <<'CB_EOF'
import json, os
from ansible.plugins.callback import CallbackBase

def objs(x, out):
    if isinstance(x, dict):
        md = x.get("metadata")
        if x.get("kind") and isinstance(md, dict) and md.get("name"):
            out.append({"kind": x["kind"], "name": md["name"], "namespace": md.get("namespace")})
        for v in x.values():
            objs(v, out)
    elif isinstance(x, list):
        for v in x:
            objs(v, out)

class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "aggregate"
    CALLBACK_NAME = "badge_audit"
    CALLBACK_NEEDS_ENABLED = True

    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        self.rows = []

    def _rec(self, result, status):
        found = []
        objs(result._result, found)
        self.rows.append({"action": result._task.action, "status": status,
                          "changed": bool(result._result.get("changed")), "objects": found,
                          "msg": str(result._result.get("msg", ""))[:400]})

    def v2_runner_on_ok(self, result): self._rec(result, "ok")
    def v2_runner_on_failed(self, result, ignore_errors=False): self._rec(result, "failed")
    def v2_runner_on_skipped(self, result): self._rec(result, "skipped")

    def v2_playbook_on_stats(self, stats):
        with open(os.environ["BADGE_AUDIT"], "w") as f:
            json.dump(self.rows, f)
CB_EOF

# --- self-serve grader (run `check`) ---
cat > /usr/local/bin/check <<'BADGE_CHECK_EOF'
#!/usr/bin/env python3
# Pass when my-app/nginx runs and answers, was created through the Kubernetes API
# by Ansible (not kubectl), and the committed playbook, run in --check mode from a
# clean environment, uses kubernetes.core.k8s for the namespace, Deployment and
# Service and reports no changes (idempotent and matches the live state).
import json, os, re, subprocess, sys, tempfile, time, urllib.request

REPO = "/root/ansible-k8s"
PB = "deploy-to-k8s.yaml"
NS = "my-app"
KC = ["k3s", "kubectl", "--kubeconfig", "/etc/rancher/k3s/k3s.yaml"]
K8S_ACTIONS = {"kubernetes.core.k8s", "k8s", "community.kubernetes.k8s"}

def fail(msg):
    print(f"❌ NOT YET: {msg}"); sys.exit(0)

def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    return r.returncode, r.stdout, r.stderr

def kget(*args):
    rc, out, _ = run(KC + list(args) + ["-o", "json"])
    return json.loads(out) if rc == 0 and out else None

# playbook committed
os.path.isfile(f"{REPO}/{PB}") or fail(f"No playbook {REPO}/{PB}.")
rc, out, _ = run(["git", "-C", REPO, "ls-files", "--error-unmatch", PB])
rc == 0 or fail(f"{PB} is not committed to the git repo in {REPO}.")
rc, out, _ = run(["git", "-C", REPO, "status", "--porcelain", "--", PB])
out.strip() and fail(f"{PB} has uncommitted changes; commit them.")

# cluster state
kget("get", "ns", NS) or fail(f"Namespace {NS} does not exist.")
dep = kget("-n", NS, "get", "deploy", "nginx") or fail(f"No Deployment nginx in namespace {NS}.")
svc = kget("-n", NS, "get", "svc", "nginx") or fail(f"No Service nginx in namespace {NS}.")

def by_kubectl(obj):
    return sorted({m.get("manager", "") for m in obj["metadata"].get("managedFields") or []
                   if m.get("manager", "").startswith(("kubectl", "k3s-")) and not m.get("subresource")})

for kind, obj in (("Deployment", dep), ("Service", svc)):
    k = by_kubectl(obj)
    k and fail(f"{kind} nginx was created or changed with kubectl ({', '.join(k)}); it must come from your Ansible playbook only. Delete it and deploy it with the playbook.")

want = dep["spec"].get("replicas") or 1
st = dep.get("status") or {}
if st.get("observedGeneration", 0) < dep["metadata"]["generation"] or (st.get("updatedReplicas") or 0) < want \
        or (st.get("availableReplicas") or 0) < want:
    fail(f"Deployment nginx is not fully rolled out ({st.get('availableReplicas') or 0}/{want} available); kubectl -n {NS} get pods.")

ip = svc["spec"].get("clusterIP")
port = (svc["spec"].get("ports") or [{}])[0].get("port", 80)
for _ in range(5):
    try:
        code = urllib.request.urlopen(f"http://{ip}:{port}/", timeout=10).status
    except Exception as e:
        code = getattr(e, "code", None) or str(e)
    if code == 200:
        break
    time.sleep(2)
code == 200 or fail(f"Service nginx ({ip}:{port}) does not answer HTTP 200 (got {code}).")

# the playbook itself, in check mode from a clean environment
audit = tempfile.mktemp(suffix=".json")
env = {"PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", "HOME": "/root",
       "LANG": "C.UTF-8", "ANSIBLE_NOCOLOR": "1", "ANSIBLE_CALLBACK_PLUGINS": "/opt/badge/callback",
       "ANSIBLE_CALLBACKS_ENABLED": "badge_audit", "BADGE_AUDIT": audit}
try:
    rc, out, err = run(["ansible-playbook", PB, "--check", "--diff"], cwd=REPO, env=env, timeout=300)
except subprocess.TimeoutExpired:
    fail(f"ansible-playbook {PB} --check did not finish within 5 minutes.")
try:
    rows = json.load(open(audit)); os.unlink(audit)
except Exception:
    rows = []
failed = [r for r in rows if r["status"] == "failed"]
if rc != 0 or failed:
    msg = failed[0]["msg"] if failed and failed[0]["msg"] else (err.strip() or out.strip()).splitlines()[-1:]
    fail(f"`ansible-playbook {PB} --check --diff` fails when run from {REPO} in a fresh shell: {msg if isinstance(msg, str) else ' '.join(msg)}")

touched = {(o["kind"], o["name"], o.get("namespace")) for r in rows if r["action"] in K8S_ACTIONS for o in r["objects"]}
for kind, name, ns in (("Namespace", NS, None), ("Deployment", "nginx", NS), ("Service", "nginx", NS)):
    (kind, name, ns) in touched or fail(f"Your playbook does not manage {kind} {name}{' in ' + ns if ns else ''} with the kubernetes.core.k8s module.")
SHELLISH = re.compile(r"^(ansible\.builtin\.|ansible\.legacy\.)?(command|shell|raw|script)$")
skipped = [r["action"] for r in rows if r["status"] == "skipped" and SHELLISH.match(r["action"])]
skipped and fail(f"Your playbook runs {', '.join(sorted(set(skipped)))} tasks, which cannot run in check mode; the deployment must be done with kubernetes.core modules.")
changed = [r for r in rows if r["changed"]]
changed and fail(f"Running the playbook again would change {len(changed)} task(s) (it is not idempotent or the cluster differs from it); see `ansible-playbook {PB} --check --diff`.")

print(f"✅ PASS: the playbook creates namespace {NS} and deploys nginx with kubernetes.core, the app answers HTTP 200, and a re-run changes nothing.")
BADGE_CHECK_EOF
chmod +x /usr/local/bin/check

wait
touch /tmp/setup-done

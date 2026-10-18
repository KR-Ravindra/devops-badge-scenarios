#!/bin/bash
# Seeds: a "cloud server" container (sshd + nginx front on :8080 + docker CLI)
# serving the app container nginx-app, a Linode-API-shaped mock on :8000 that can
# reboot it, Mailpit as the SMTP server, pinned Python libs, and an empty
# /root/monitoring. The candidate writes and runs monitor.py. Installs `check`.
# Course reference: gitlab.com/twn-devops-bootcamp/latest/14-automation-with-python/
#   automation-projects @ fb3d2f537cb599e734ba6c24683b179bb8ae3840 (monitor-website.py,
#   the solution, so it is NOT copied into the starter).
exec >>/var/log/badge-setup.log 2>&1
set -x
trap 'touch /tmp/setup-failed' ERR
set -eE

NGINX_IMG=nginx:1.30.4-alpine
DEBIAN_IMG=debian:13.6-slim
DOCKER_CLI_IMG=docker:29.8.1-cli
MAILPIT_IMG=axllent/mailpit:v1.31.3
PY_PKGS="requests==2.34.2 paramiko==5.0.0 schedule==1.2.2 linode-api4==5.47.0"
NET=cloud-net SUBNET=192.168.77.0/24 SERVER_IP=192.168.77.10 APP_IP=192.168.77.20
INSTANCE_ID=61420077
LAB=/etc/badge-lab

# --- Docker ---
if ! command -v docker >/dev/null; then curl -fsSL https://get.docker.com | sh; fi
systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done

for img in $NGINX_IMG $DEBIAN_IMG $DOCKER_CLI_IMG $MAILPIT_IMG; do docker pull -q $img & done

# --- Python libs (the ones the course uses) ---
( python3 -m pip --version >/dev/null 2>&1 || { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-pip; }
  python3 -m pip install -q --break-system-packages --ignore-installed $PY_PKGS \
    || python3 -m pip install -q --ignore-installed $PY_PKGS ) &
wait

# --- lab secrets (kept on re-run) ---
mkdir -p $LAB && chmod 700 $LAB
if [ ! -f $LAB/secrets.env ]; then
  { echo "LINODE_TOKEN=$(openssl rand -hex 32)"; echo "EMAIL_PASSWORD=$(openssl rand -hex 12)"; } > $LAB/secrets.env
fi
. $LAB/secrets.env
chmod 600 $LAB/secrets.env

# --- SSH key for the server ---
mkdir -p /root/.ssh && chmod 700 /root/.ssh
[ -f /root/.ssh/cloud_server_key ] || ssh-keygen -q -t ed25519 -N '' -C web-server -f /root/.ssh/cloud_server_key

# --- "cloud server" image: sshd + nginx on :8080 in front of the app + docker CLI ---
B=/opt/badge-lab/web-server
rm -rf $B && mkdir -p $B
cp /root/.ssh/cloud_server_key.pub $B/authorized_keys
cat > $B/Dockerfile <<EOF
FROM $DOCKER_CLI_IMG AS dockercli
FROM $DEBIAN_IMG
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssh-server nginx \\
 && rm -rf /var/lib/apt/lists/* /etc/nginx/sites-enabled/* && mkdir -p /run/sshd /root/.ssh && ssh-keygen -A
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker.real
COPY docker /usr/local/bin/docker
COPY authorized_keys /root/.ssh/authorized_keys
COPY site.conf /etc/nginx/conf.d/site.conf
COPY start.sh /start.sh
RUN chmod 600 /root/.ssh/authorized_keys && chmod +x /usr/local/bin/docker /start.sh
CMD ["/start.sh"]
EOF
cat > $B/docker <<'EOF'
#!/bin/sh
echo "$(date +%s) $*" >> /var/log/docker-cmds.log
exec /usr/local/bin/docker.real "$@"
EOF
cat > $B/site.conf <<EOF
server {
    listen 8080;
    location / {
        proxy_pass http://$APP_IP:80;
        proxy_connect_timeout 2s;
    }
}
EOF
cat > $B/start.sh <<'EOF'
#!/bin/sh
/usr/sbin/sshd
exec nginx -g 'daemon off;'
EOF
docker build -q -t badge-web-server:1 $B

# --- network, app, server, mail ---
docker rm -f web-server nginx-app mailpit 2>/dev/null || true
docker network inspect $NET >/dev/null 2>&1 || docker network create --subnet $SUBNET $NET
docker run -d --name nginx-app --network $NET --ip $APP_IP $NGINX_IMG
docker run -d --name web-server --hostname web-server --network $NET --ip $SERVER_IP \
  -v /var/run/docker.sock:/var/run/docker.sock badge-web-server:1
docker run -d --name mailpit --restart=always -p 127.0.0.1:1025:1025 -p 8025:8025 \
  -e MP_SMTP_AUTH="alerts@lab.local:$EMAIL_PASSWORD" -e MP_SMTP_AUTH_ALLOW_INSECURE=true \
  -e MP_MAX_MESSAGES=500 $MAILPIT_IMG

# --- cloud API stand-in (Linode API v4 shape) ---
mkdir -p /opt/badge-lab/cloud-api /var/lib/cloud-api
cat > /opt/badge-lab/cloud-api/api.py <<'API_EOF'
#!/usr/bin/env python3
# Minimal Linode API v4 stand-in for one instance backed by the web-server container.
# A paused container is a hung VM: the provider still reports it "running".
import json, os, subprocess, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = os.environ["LINODE_TOKEN"]
IID = int(os.environ["INSTANCE_ID"])
SERVER, APP = "web-server", "nginx-app"
LOG = "/var/lib/cloud-api/requests.log"
state = {"rebooting": False}
lock = threading.Lock()

def docker(*a):
    return subprocess.run(["docker", *a], capture_output=True, text=True)

def status():
    if state["rebooting"]:
        return "rebooting"
    r = docker("inspect", "-f", "{{.State.Running}}", SERVER)
    return "running" if r.stdout.strip() == "true" else "offline"

def reboot():
    try:
        docker("stop", "-t", "1", APP)       # containers don't come back on their own after a reboot
        docker("unpause", SERVER)
        docker("restart", "-t", "2", SERVER)
        time.sleep(6)
    finally:
        state["rebooting"] = False

def instance():
    now = time.strftime("%Y-%m-%dT%H:%M:%S")
    return {"id": IID, "label": "web-server", "group": "", "status": status(), "type": "g6-nanode-1",
            "region": "eu-central", "image": "linode/debian12", "hypervisor": "kvm",
            "ipv4": ["192.168.77.10"], "ipv6": None, "created": "2026-01-01T00:00:00", "updated": now,
            "specs": {"disk": 25600, "memory": 1024, "vcpus": 1, "transfer": 1000, "gpus": 0},
            "alerts": {}, "backups": {"enabled": False}, "tags": [], "watchdog_enabled": True}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, body):
        b = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def handle_any(self, method):
        path = self.path.split("?")[0].rstrip("/")
        auth = self.headers.get("Authorization", "") == f"Bearer {TOKEN}"
        n = int(self.headers.get("Content-Length") or 0)
        if n:
            self.rfile.read(n)
        with open(LOG, "a") as f:
            f.write(json.dumps({"ts": time.time(), "method": method, "path": path, "auth": auth}) + "\n")
        if not auth:
            return self.reply(401, {"errors": [{"reason": "Invalid Token"}]})
        base = f"/v4/linode/instances/{IID}"
        if method == "GET" and path == base:
            return self.reply(200, instance())
        if method == "GET" and path == "/v4/linode/instances":
            return self.reply(200, {"data": [instance()], "page": 1, "pages": 1, "results": 1})
        if method == "POST" and path in (base + "/reboot", base + "/boot"):
            with lock:
                if not state["rebooting"]:
                    state["rebooting"] = True
                    threading.Thread(target=reboot, daemon=True).start()
            return self.reply(200, {})
        if path.startswith("/v4/linode/instances/"):
            return self.reply(404, {"errors": [{"reason": "Not found"}]})
        return self.reply(404, {"errors": [{"reason": "Not found"}]})

    def do_GET(self):
        self.handle_any("GET")

    def do_POST(self):
        self.handle_any("POST")

ThreadingHTTPServer(("0.0.0.0", 8000), H).serve_forever()
API_EOF
cat > /etc/systemd/system/cloud-api.service <<EOF
[Unit]
Description=Cloud provider API (lab stand-in)
After=docker.service
[Service]
Environment=LINODE_TOKEN=$LINODE_TOKEN
Environment=INSTANCE_ID=$INSTANCE_ID
ExecStart=/usr/bin/python3 /opt/badge-lab/cloud-api/api.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF
chmod 600 /etc/systemd/system/cloud-api.service
systemctl daemon-reload
systemctl enable cloud-api
systemctl restart cloud-api

# --- candidate's starting point ---
mkdir -p /root/monitoring
cat > /root/cloud-credentials.txt <<EOF
# Handed to you by the cloud provider and the mail provider. Treat as secrets.
LINODE_TOKEN=$LINODE_TOKEN
EMAIL_ADDRESS=alerts@lab.local
EMAIL_PASSWORD=$EMAIL_PASSWORD
EOF
chmod 600 /root/cloud-credentials.txt

# --- wait until everything answers ---
for i in $(seq 1 60); do
  curl -sf -o /dev/null http://$SERVER_IP:8080/ && curl -sf -o /dev/null http://localhost:8025/api/v1/info \
    && curl -s -o /dev/null http://localhost:8000/ && break
  sleep 2
done
curl -sf -o /dev/null http://$SERVER_IP:8080/
ssh -i /root/.ssh/cloud_server_key -o StrictHostKeyChecking=accept-new -o BatchMode=yes root@$SERVER_IP true
python3 -c "import requests, paramiko, schedule, linode_api4"

# --- check ---
cat > /usr/local/bin/check <<'BADGE_CHECK_EOF'
#!/usr/bin/env python3
# Pass when a monitor.py process is running that (1) alerts and restarts the app
# container over SSH when the site returns an error, and (2) alerts, reboots the
# server through the cloud API and brings the app back when the server hangs.
# The grader breaks things for real and waits for the candidate's automation.
import glob, json, os, subprocess, sys, time, urllib.request

SERVER_IP, SITE = "192.168.77.10", "http://192.168.77.10:8080/"
MAILPIT = "http://localhost:8025/api/v1/messages"
REBOOT_LOG = "/var/lib/cloud-api/requests.log"
ALERT_TO = "ops@lab.local"
secrets = dict(l.strip().split("=", 1) for l in open("/etc/badge-lab/secrets.env") if "=" in l)

def fail(msg):
    restore()
    print(f"❌ NOT YET: {msg}"); sys.exit(0)

def sh(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True)

def state(name):
    r = sh("docker", "inspect", "-f", "{{.State.Status}}", name)
    return r.stdout.strip() or "missing"

def http_status():
    try:
        return urllib.request.urlopen(SITE, timeout=3).status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return None

def restore():
    if state("web-server") == "paused":
        sh("docker", "unpause", "web-server")
    if state("web-server") != "running":
        sh("docker", "start", "web-server")
    if state("nginx-app") != "running":
        sh("docker", "start", "nginx-app")

def alerts():
    try:
        d = json.load(urllib.request.urlopen(MAILPIT + "?limit=200", timeout=3))
    except Exception:
        return 0
    return sum(1 for m in d.get("messages", []) if any(t.get("Address", "").lower() == ALERT_TO for t in m.get("To") or []))

def clear_mail():
    urllib.request.urlopen(urllib.request.Request(MAILPIT, method="DELETE"), timeout=3)

def reboots():
    ok = bad = 0
    try:
        for l in open(REBOOT_LOG):
            e = json.loads(l)
            if e["method"] == "POST" and e["path"].endswith(("/reboot", "/boot")):
                ok, bad = (ok + 1, bad) if e["auth"] else (ok, bad + 1)
    except FileNotFoundError:
        pass
    return ok, bad

def app_starts():
    r = sh("docker", "exec", "web-server", "sh", "-c", "cat /var/log/docker-cmds.log 2>/dev/null")
    return sum(1 for l in r.stdout.splitlines() if "nginx-app" in l and (" start" in l or " restart" in l))

def monitor_pids():
    pids = []
    for p in glob.glob("/proc/[0-9]*/cmdline"):
        try:
            argv = open(p, "rb").read().split(b"\0")
        except OSError:
            continue
        if argv and b"python" in os.path.basename(argv[0]) and any(a.endswith(b"monitor.py") for a in argv[1:]):
            pids.append(p.split("/")[2])
    return pids

def healthy():
    return state("web-server") == "running" and state("nginx-app") == "running" and http_status() == 200

# --- static: the script exists and keeps secrets out of the code ---
code = "/root/monitoring/monitor.py"
os.path.isfile(code) or fail(f"{code} does not exist.")
for f in glob.glob("/root/monitoring/**/*.py", recursive=True):
    txt = open(f, errors="ignore").read()
    for k in ("LINODE_TOKEN", "EMAIL_PASSWORD"):
        if secrets[k] in txt:
            fail(f"{f} contains the literal {k}. Credentials must come from environment variables, not the code.")
monitor_pids() or fail("No monitor.py process is running. Start it so it keeps running in the background, then run check again.")

# --- baseline ---
restore()
for _ in range(20):
    if healthy():
        break
    time.sleep(1)
else:
    fail(f"Lab baseline broken: {SITE} does not return 200 even after restoring the containers (docker ps -a).")
time.sleep(3)

# --- stage 1: the app container dies, the server is fine ---
print("Stage 1/2: stopping the app container nginx-app on the server (the site returns an error)...", flush=True)
clear_mail()
r0, s0 = reboots()[0], app_starts()
sh("docker", "stop", "-t", "1", "nginx-app")
t = time.time()
while time.time() - t < 75:
    time.sleep(3)
    if alerts() and healthy() and app_starts() > s0:
        break
monitor_pids() or fail("Stage 1 (app down): your monitor.py process exited. It has to keep running.")
alerts() or fail(f"Stage 1 (app down): the site returned an error status but no alert email reached {ALERT_TO} within 75s.")
state("nginx-app") == "running" or fail("Stage 1 (app down): an alert was sent but nginx-app was not started again within 75s.")
app_starts() > s0 or fail("Stage 1 (app down): nginx-app came back, but not through a docker command run on the server (SSH into web-server).")
http_status() == 200 or fail(f"Stage 1 (app down): nginx-app is running but {SITE} still doesn't return 200.")
reboots()[0] == r0 or fail("Stage 1 (app down): only the app container was down and the server was healthy, but your monitor rebooted the whole server.")
print(f"  ok: alert sent and app back after {int(time.time() - t)}s", flush=True)
time.sleep(8)

# --- stage 2: the server hangs (SSH and HTTP accept connections but never answer) ---
print("Stage 2/2: freezing the server web-server (unreachable, the cloud API still says running)...", flush=True)
clear_mail()
(r0, b0), s0 = reboots(), app_starts()
sh("docker", "pause", "web-server")
t = time.time()
while time.time() - t < 150:
    time.sleep(3)
    if alerts() and reboots()[0] > r0 and healthy() and app_starts() > s0:
        break
monitor_pids() or fail("Stage 2 (server down): your monitor.py process exited. It has to keep running.")
alerts() or fail(f"Stage 2 (server down): the server stopped responding but no alert email reached {ALERT_TO} within 150s.")
if reboots()[0] == r0:
    if reboots()[1] > b0:
        fail("Stage 2 (server down): your monitor called the reboot endpoint but the API rejected the token (401).")
    fail("Stage 2 (server down): an alert was sent but the server was never rebooted through the cloud API.")
state("web-server") == "running" or fail("Stage 2 (server down): the reboot was requested but web-server is not running again.")
(state("nginx-app") == "running" and app_starts() > s0) or fail("Stage 2 (server down): the server rebooted but nginx-app was not started again on it (a reboot does not bring containers back).")
http_status() == 200 or fail(f"Stage 2 (server down): server and app are up but {SITE} doesn't return 200.")
print(f"  ok: alert sent, server rebooted and app back after {int(time.time() - t)}s", flush=True)
print("✅ PASS: monitor.py alerts and restarts the app over SSH when the site fails, and reboots the server through the cloud API and recovers the app when the server hangs.")
BADGE_CHECK_EOF
chmod +x /usr/local/bin/check

touch /tmp/setup-done

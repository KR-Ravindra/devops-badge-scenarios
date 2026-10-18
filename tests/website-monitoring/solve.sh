#!/bin/bash
# Reference solution: monitor.py (requests + smtplib + paramiko + linode_api4 +
# schedule, with timeouts) run as a systemd service with the secrets in an
# EnvironmentFile. Used by CI to prove the scenario is solvable.
set -euo pipefail
mkdir -p /root/monitoring
cat > /root/monitoring/monitor.py <<'EOF'
import os
import smtplib
import time
from email.message import EmailMessage

import linode_api4
import paramiko
import requests
import schedule

URL = 'http://192.168.77.10:8080/'
SERVER_IP = '192.168.77.10'
INSTANCE_ID = 61420077
LINODE_TOKEN = os.environ['LINODE_TOKEN']
EMAIL_ADDRESS = os.environ['EMAIL_ADDRESS']
EMAIL_PASSWORD = os.environ['EMAIL_PASSWORD']


def send_notification(body):
    print('Sending an email...', flush=True)
    msg = EmailMessage()
    msg['Subject'] = 'SITE DOWN'
    msg['From'] = EMAIL_ADDRESS
    msg['To'] = 'ops@lab.local'
    msg.set_content(body)
    with smtplib.SMTP('localhost', 1025, timeout=10) as smtp:
        smtp.login(EMAIL_ADDRESS, EMAIL_PASSWORD)
        smtp.send_message(msg)


def restart_container():
    print('Restarting the application...', flush=True)
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(SERVER_IP, username='root', key_filename='/root/.ssh/cloud_server_key',
                timeout=10, banner_timeout=10, auth_timeout=10)
    try:
        _, stdout, _ = ssh.exec_command('docker start nginx-app', timeout=30)
        stdout.channel.recv_exit_status()
    finally:
        ssh.close()


def restart_server_and_container():
    print('Rebooting the server...', flush=True)
    client = linode_api4.LinodeClient(LINODE_TOKEN, base_url='http://localhost:8000/v4')
    client.load(linode_api4.Instance, INSTANCE_ID).reboot()
    deadline = time.time() + 300
    while time.time() < deadline:
        time.sleep(3)
        if client.load(linode_api4.Instance, INSTANCE_ID).status == 'running':
            break
    for _ in range(10):
        try:
            restart_container()
            return
        except Exception as ex:
            print(f'SSH not ready yet: {ex}', flush=True)
            time.sleep(3)


def monitor_application():
    try:
        try:
            response = requests.get(URL, timeout=5)
        except requests.RequestException as ex:
            print(f'Connection error: {ex}', flush=True)
            send_notification('Server not reachable at all, rebooting it.')
            restart_server_and_container()
            return
        if response.status_code == 200:
            print('Application is running', flush=True)
        else:
            send_notification(f'Application returned {response.status_code}')
            restart_container()
    except Exception as ex:
        print(f'Recovery failed: {ex}', flush=True)


schedule.every(10).seconds.do(monitor_application)
while True:
    schedule.run_pending()
    time.sleep(1)
EOF

cat > /etc/systemd/system/website-monitor.service <<'EOF'
[Unit]
Description=Website monitor
After=network-online.target
[Service]
EnvironmentFile=/root/cloud-credentials.txt
ExecStart=/usr/bin/python3 /root/monitoring/monitor.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable website-monitor
systemctl restart website-monitor
sleep 5
systemctl is-active website-monitor

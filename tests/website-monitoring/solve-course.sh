#!/bin/bash
# Course-faithful solution: the bootcamp's monitor-website.py
# (twn-devops-bootcamp/latest/14-automation-with-python/automation-projects
#  @ fb3d2f53) with only the changes the lab's stand-ins and task text require:
#  - URL / server IP / key path / instance ID of this lab
#  - LinodeClient(..., base_url=<stand-in API>)        (stand-in, documented in intro)
#  - SMTP localhost:1025 without starttls()            (stand-in, documented in intro)
#  - recipient ops@lab.local                           (task text)
#  - requests.get(..., timeout=10)                     (task text: server can hang)
#  - schedule every 10 seconds instead of 5 minutes    (task text: <= 30s)
# Everything else (sendmail without headers, docker start <container-id>, busy
# loops, no sleep in the main loop) is kept as the course writes it. Started the
# way a candidate would: nohup in the background with the env vars exported.
set -euo pipefail
mkdir -p /root/monitoring
CID=$(docker inspect -f '{{.Id}}' nginx-app | cut -c1-12)
cat > /root/monitoring/monitor.py <<EOF2
import requests
import smtplib
import os
import paramiko
import linode_api4
import time
import schedule

EMAIL_ADDRESS = os.environ.get('EMAIL_ADDRESS')
EMAIL_PASSWORD = os.environ.get('EMAIL_PASSWORD')
LINODE_TOKEN = os.environ.get('LINODE_TOKEN')


def restart_server_and_container():
    # restart linode server
    print('Rebooting the server...')
    client = linode_api4.LinodeClient(LINODE_TOKEN, base_url='http://localhost:8000/v4')
    nginx_server = client.load(linode_api4.Instance, 61420077)
    nginx_server.reboot()

    # restart the application
    while True:
        nginx_server = client.load(linode_api4.Instance, 61420077)
        if nginx_server.status == 'running':
            time.sleep(5)
            restart_container()
            break


def send_notification(email_msg):
    print('Sending an email...')
    with smtplib.SMTP('localhost', 1025) as smtp:
        smtp.ehlo()
        smtp.login(EMAIL_ADDRESS, EMAIL_PASSWORD)
        message = f"Subject: SITE DOWN\n{email_msg}"
        smtp.sendmail(EMAIL_ADDRESS, 'ops@lab.local', message)


def restart_container():
    print('Restarting the application...')
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(hostname='192.168.77.10', username='root', key_filename='/root/.ssh/cloud_server_key')
    stdin, stdout, stderr = ssh.exec_command('docker start $CID')
    print(stdout.readlines())
    ssh.close()


def monitor_application():
    try:
        response = requests.get('http://192.168.77.10:8080/', timeout=10)
        if response.status_code == 200:
            print('Application is running successfully!')
        else:
            print('Application Down. Fix it!')
            msg = f'Application returned {response.status_code}'
            send_notification(msg)
            restart_container()
    except Exception as ex:
        print(f'Connection error happened: {ex}')
        msg = 'Application not accessible at all'
        send_notification(msg)
        restart_server_and_container()


schedule.every(10).seconds.do(monitor_application)

while True:
    schedule.run_pending()
EOF2

set -a; . /root/cloud-credentials.txt; set +a
cd /root/monitoring
nohup setsid python3 -u monitor.py > /root/monitoring/monitor.log 2>&1 < /dev/null &
sleep 5
pgrep -f 'python3 -u monitor.py' >/dev/null

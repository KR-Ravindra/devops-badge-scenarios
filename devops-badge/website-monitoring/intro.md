# Website Monitoring and Recovery

Your company's website runs as an nginx container on a single cloud server. Twice
this month it went down at night and nobody noticed until customers complained.
You're asked to write a Python program that watches the site around the clock,
alerts the team by email, and fixes the usual failures on its own.

This lab has no cloud account or real mailbox, so it uses stand-ins:

| In production | In this lab |
|---|---|
| Linode / DigitalOcean server | A server named `web-server` at `192.168.77.10` (a container on this machine). SSH as `root` with the key `/root/.ssh/cloud_server_key` |
| The website | The container `nginx-app`, run with Docker **on that server**, published at `http://192.168.77.10:8080/` |
| Cloud provider API | A Linode API v4 compatible endpoint at `http://localhost:8000/v4`. Your server is instance ID `61420077` |
| Email provider (e.g. Gmail SMTP) | An SMTP server at `localhost:1025` (no TLS, login required). Its inbox viewer is on port `8025` |

Your API token and the alert mailbox's login (`alerts@lab.local`) are in
`/root/cloud-credentials.txt`. Python 3 is installed with `requests`, `paramiko`,
`schedule` and `linode_api4`.

Setup takes a couple of minutes. Wait for the terminal to say the lab is ready, then
click **START**.

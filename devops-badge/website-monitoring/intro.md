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
| Cloud provider API (`https://api.linode.com/v4`) | A Linode API v4 compatible endpoint whose base URL is `http://localhost:8000/v4`. Your server is instance ID `61420077`. The `linode_api4` client's `LinodeClient` takes the base URL as `base_url=` |
| Email provider (e.g. Gmail SMTP on 587 with STARTTLS) | An SMTP server at `localhost:1025`. It does **not** support STARTTLS: connect in plain SMTP and log in (login is required). Its inbox viewer is on port `8025` ([open it]({{TRAFFIC_HOST1_8025}})) |

Your API token and the alert mailbox's login (`alerts@lab.local`) are in
`/root/cloud-credentials.txt`. Python 3 is installed with `requests`, `paramiko`,
`schedule` and `linode_api4`.

Setup takes a couple of minutes. Wait for the terminal to say the lab is ready, then
click **START**.

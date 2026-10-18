# Monitor the website and recover it automatically

[Open the inbox viewer]({{TRAFFIC_HOST1_8025}}) to see the emails your program sends.

Write `/root/monitoring/monitor.py`. It checks `http://192.168.77.10:8080/` on a
schedule, at least every 30 seconds, and:

1. When the site answers with anything other than HTTP 200, it emails an alert to
   `ops@lab.local` (sent from `alerts@lab.local`) and restarts the app container
   `nginx-app` on the server over SSH from Python.
2. When the server doesn't respond at all, it emails an alert, reboots the server
   through the cloud provider API, waits until the server is running again, and then
   restarts the app container on it.

Keep the credentials out of the code: the API token and the email password are read
from environment variables.

Leave the monitor running in the background so it keeps watching after you close
the terminal.

Done when the monitor is running and recovers the site from both kinds of failure.
`check` takes a few minutes: it really breaks the app, then the server, and waits
for your monitor to fix them.

> Run `check` any time to see your result. Click **Continue** to move on whenever you want — you can proceed even if it isn't passing yet.

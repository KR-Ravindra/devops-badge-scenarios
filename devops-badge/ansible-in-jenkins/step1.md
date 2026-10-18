# Configure the servers from Jenkins with Ansible

[Open Jenkins]({{TRAFFIC_HOST1_8080}}) (user `admin`, password `admin`).

Make the `java-maven-app` job do all of this in one run, and get a green build:

1. Copy your Ansible files (playbook, config, inventory) and the servers' SSH
   key to `ansible-server`.
2. Prepare `ansible-server` so it can run your playbook (install what it needs).
   This is part of the pipeline, not something you do by hand.
3. Run the playbook **on `ansible-server`**. It must:
   - find the web servers through a **dynamic inventory**, the containers with
     label `role=webserver`, and nothing else. No host names or IPs written
     down anywhere;
   - connect to them over **SSH** as `ec2-user`;
   - install Docker and the Docker Compose plugin, so that for `ec2-user` both
     `docker --version` and `docker compose version` work;
   - add `ec2-user` to the `docker` group.

Web servers get added over time. When the job runs, it must configure every web
server that exists at that moment, without changes to the pipeline or the
Ansible files.

Done when the latest Jenkins build is green and every web server is configured.
Then run `check`.

> Run `check` any time to see your result. Click **Continue** to move on whenever you want — you can proceed even if it isn't passing yet.

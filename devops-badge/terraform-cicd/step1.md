# Provision and deploy from Jenkins with Terraform

[Open Jenkins]({{TRAFFIC_HOST1_8081}}) (user `admin`, password `admin`).

Make the `java-maven-app` job do all of this in one run, and get a green build:

1. Build the application with Maven.
2. Build a Docker image of it and push it to `localhost:5000/java-maven-app`.
   Every build must produce a **new, unique tag** (not `latest`).
3. Provision the server with `terraform apply` from the `terraform/` folder.
   The Terraform state must be stored remotely in the S3 bucket `tf-state`, not on
   the Jenkins machine.
4. Deploy to that server: copy the deployment files to it over SSH and start the
   app there with `docker-compose`, running the image the build just pushed. The
   pipeline must get the server's address from Terraform, not from a hardcoded value.

The app must actually be up and answering on port `8080`, not just started.

Done when the latest Jenkins build is green, the Terraform state in `tf-state`
holds the server, and the server runs the image that build pushed. Then run `check`.

> Run `check` any time to see your result. Click **Continue** to move on whenever you want — you can proceed even if it isn't passing yet.

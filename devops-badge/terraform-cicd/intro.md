# Complete CI/CD with Terraform

Your team wants one pipeline that takes `java-maven-app` all the way from source
to a running server: build the app, publish its image, create the server it runs
on with Terraform, and deploy to it. Nobody should have to click in a console or
copy an IP address by hand.

This lab has no AWS account, so it uses stand-ins for the AWS parts:

| In production | In this lab |
|---|---|
| EC2 instance | A container created by Terraform's `kreuzwerker/docker` provider (already in the starter `terraform/` config) from the image `lab-server:1.0`: an SSH server (user `ec2-user`, home `/home/ec2-user`, key auth only) with `docker` and `docker-compose`. It drives this machine's Docker engine, so ports its containers publish are on this machine. Unlike EC2 `Name` tags, container names are unique on this machine: Terraform cannot create a server whose name is already taken by an existing container |
| EC2 key pair | Private key: Jenkins credential `server-ssh-key` (user `ec2-user`). Public key: `/root/.ssh/server-key.pub`, on this machine and, read-only at the same path, inside the Jenkins container |
| S3 bucket for Terraform state | MinIO (S3-compatible), bucket `tf-state`. Its S3 API is at `http://localhost:9000` (from this machine and from Jenkins) and serves path-style requests only (`http://host/bucket/key`). MinIO accepts any region name, but Terraform only accepts real AWS region names unless region validation is skipped. MinIO is not AWS: there is no STS or IAM, so Terraform's AWS credential validation and account-ID lookup can't succeed against it (the S3 backend has a `skip_*` setting for each). Web console: [MinIO console]({{TRAFFIC_HOST1_9001}}) |
| AWS access keys | The MinIO keys, stored in Jenkins as secret text `jenkins_aws_access_key_id` / `jenkins-aws_secret_access_key` (`labadmin` / `labsecret123`, also the console login) |
| Docker Hub / ECR | A private registry at `localhost:5000` (no login needed) |
| Jenkins server | Jenkins in a Docker container named `jenkins` on port `8081`, user `admin` / password `admin`. Maven (tool name `Maven`), the docker CLI and `terraform` are installed in it. No Jenkins shared library and no GitLab or Docker Hub credentials are set up in it |

The app's code is in `/root/java-maven-app` (a git repo, branch `master`), with a
Terraform config for the server in `terraform/`. A pipeline job called
`java-maven-app` already exists in Jenkins and builds the `Jenkinsfile` from the
`master` branch of that repo, so Jenkins only sees what you **commit**.

Setup takes a few minutes. Wait for the terminal to say the lab is ready, then
click **START**.

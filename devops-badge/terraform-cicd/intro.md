# Complete CI/CD with Terraform

Your team wants one pipeline that takes `java-maven-app` all the way from source
to a running server: build the app, publish its image, create the server it runs
on with Terraform, and deploy to it. Nobody should have to click in a console or
copy an IP address by hand.

This lab has no AWS account, so it uses stand-ins for the AWS parts:

| In production | In this lab |
|---|---|
| EC2 instance | A container created by Terraform's `kreuzwerker/docker` provider from the image `lab-server:1.0`: an SSH server (user `ec2-user`, key auth only) with `docker` and `docker-compose`. It drives this machine's Docker engine, so ports its containers publish are on this machine |
| EC2 key pair | Private key: Jenkins credential `server-ssh-key` (user `ec2-user`). Public key: `/root/.ssh/server-key.pub` |
| S3 bucket for Terraform state | MinIO at `http://localhost:9000` (console on `:9001`), bucket `tf-state`, any region name |
| AWS access keys | The MinIO keys, stored in Jenkins as secret text `jenkins_aws_access_key_id` / `jenkins-aws_secret_access_key` (`labadmin` / `labsecret123`) |
| Docker Hub / ECR | A private registry at `localhost:5000` (no login needed) |
| Jenkins server | Jenkins in a Docker container named `jenkins` on port `8081`, user `admin` / password `admin` (Maven, docker CLI and `terraform` installed) |

The app's code is in `/root/java-maven-app` (a git repo, branch `master`), with a
Terraform config for the server in `terraform/`. A pipeline job called
`java-maven-app` already exists in Jenkins and builds the `Jenkinsfile` from the
`master` branch of that repo, so Jenkins only sees what you **commit**.

Setup takes a few minutes. Wait for the terminal to say the lab is ready, then
click **START**.

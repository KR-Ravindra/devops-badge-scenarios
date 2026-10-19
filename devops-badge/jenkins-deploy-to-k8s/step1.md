# Build, push and deploy from Jenkins

[Open Jenkins]({{TRAFFIC_HOST1_8080}}) (user `admin`, password `admin`).

Make the `java-maven-app` job do all of this in one run, and get a green build:

1. Build the application with Maven.
2. Build a Docker image of it and push it to `localhost:5000/java-maven-app`.
   Every build must produce a **new, unique tag** (not `latest`).
3. Deploy it to the cluster in namespace `prod`:
   - a Deployment named `java-maven-app` running the image the build just pushed,
   - a Service named `java-maven-app` that serves the app on port `8080`
     (the app's page at `/`).

The app must actually be up and answering, not just deployed.

Done when the latest Jenkins build is green and the pods in `prod` run the image
that build pushed. Then run `check`.

> Run `check` any time to see your result. Click **Continue** to move on whenever you want — you can proceed even if it isn't passing yet.

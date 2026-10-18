#!/bin/bash
# Trigger the java-maven-app job, wait for it, then wait for the app to answer.
set -euo pipefail
J=http://localhost:8081
C=$(mktemp); CRUMB=$(curl -sf -c $C -u admin:admin "$J/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22:%22,//crumb)")
prev=$(curl -s -u admin:admin $J/job/java-maven-app/lastBuild/buildNumber || echo 0)
curl -sf -b $C -u admin:admin -H "$CRUMB" -X POST $J/job/java-maven-app/build
for i in $(seq 1 60); do
  n=$(curl -s -u admin:admin $J/job/java-maven-app/lastBuild/buildNumber || echo 0)
  [ "$n" != "$prev" ] && break; sleep 3
done
for i in $(seq 1 180); do
  s=$(curl -s -u admin:admin $J/job/java-maven-app/lastBuild/api/json || true)
  echo "$s" | grep -q '"building":false' && break; sleep 5
done
curl -s -u admin:admin $J/job/java-maven-app/lastBuild/consoleText | tail -60
for i in $(seq 1 40); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/)" = 200 ] && break; sleep 3
done

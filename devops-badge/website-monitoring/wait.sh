#!/bin/bash
echo "Preparing the lab (cloud server, cloud API, mail server). This takes a couple of minutes..."
end=$(( $(date +%s) + 900 ))
while [ ! -f /tmp/setup-done ] && [ ! -f /tmp/setup-failed ] && [ "$(date +%s)" -lt "$end" ]; do sleep 3; printf '.'; done
echo
if [ -f /tmp/setup-done ]; then
  echo "Lab is ready. Click START."
else
  [ -f /tmp/setup-failed ] || echo "Setup did not finish within 15 minutes."
  tail -25 /var/log/badge-setup.log
  echo "Setup failed — tell the exam team."
fi

#!/bin/bash
echo "Preparing the lab (cluster, Ansible). This takes a few minutes..."
end=$((SECONDS + 900))
while [ ! -f /tmp/setup-done ] && [ ! -f /tmp/setup-failed ] && [ $SECONDS -lt $end ]; do sleep 3; printf '.'; done
echo
if [ -f /tmp/setup-done ]; then
  echo "Lab is ready. Click START."
else
  tail -25 /var/log/badge-setup.log
  echo
  echo "Setup failed — tell the exam team."
fi

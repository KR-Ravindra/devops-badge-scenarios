#!/bin/bash
echo "Preparing the lab (cluster, registry, Jenkins). This takes a few minutes..."
end=$(( $(date +%s) + 900 ))
while [ ! -f /tmp/setup-done ] && [ ! -f /tmp/setup-failed ] && [ "$(date +%s)" -lt "$end" ]; do sleep 3; printf '.'; done
echo
if [ -f /tmp/setup-done ]; then
  echo "Lab is ready. Click START."
else
  tail -25 /var/log/badge-setup.log
  echo "Setup failed — tell the exam team."
fi

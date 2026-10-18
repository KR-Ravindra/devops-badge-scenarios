#!/bin/bash
echo "Preparing the lab (cluster, Helm, app images). This takes a few minutes..."
while [ ! -f /tmp/setup-done ] && [ ! -f /tmp/setup-failed ]; do sleep 3; printf '.'; done
echo
if [ -f /tmp/setup-failed ]; then echo "Setup failed: see /var/log/badge-setup.log"; else echo "Lab is ready. Click START."; fi

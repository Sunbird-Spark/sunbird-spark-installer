#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "==> Installing python3, curl, ca-certificates..."
apt-get update -qq
apt-get install -y -qq --no-install-recommends python3 curl ca-certificates

echo "==> Downloading kubectl (v1.28.0)..."
curl -fL --connect-timeout 30 --max-time 180 --retry 3 --retry-delay 5 \
  -o /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl
kubectl version --client=true || true

echo "==> Running user-progress-sync.py..."
python3 /scripts/user-progress-sync.py

echo "User progress sync completed successfully!"

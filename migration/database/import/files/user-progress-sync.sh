#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

# Skip apt-get + kubectl download if base image already has them (e.g. alpine/k8s)
need_apt=0
command -v python3   >/dev/null 2>&1 || need_apt=1
command -v curl      >/dev/null 2>&1 || need_apt=1

if [ "$need_apt" = "1" ]; then
  echo "==> Installing python3, curl, ca-certificates..."
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends python3 curl ca-certificates
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "==> Downloading kubectl (v1.28.0)..."
  curl -fL --connect-timeout 30 --max-time 180 --retry 3 --retry-delay 5 \
    -o /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
  chmod +x /usr/local/bin/kubectl
fi
kubectl version --client=true || true

echo "==> Running user-progress-sync.py..."
python3 /scripts/user-progress-sync.py

echo "User progress sync completed successfully!"

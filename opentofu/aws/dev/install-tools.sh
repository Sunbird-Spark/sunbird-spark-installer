#!/bin/bash
set -e

echo "=== Installing required tools ==="

echo "Installing jq..."
sudo apt-get update -qq
sudo apt-get install -y jq unzip

echo "Installing opentofu v1.11.4..."
curl -Lo /tmp/opentofu.tar.gz \
  https://github.com/opentofu/opentofu/releases/download/v1.11.4/tofu_1.11.4_linux_amd64.tar.gz
tar -xzf /tmp/opentofu.tar.gz -C /tmp
sudo mv /tmp/tofu /usr/local/bin/tofu

echo "Installing terragrunt v0.77.5..."
sudo wget -qO /usr/local/bin/terragrunt \
  https://github.com/gruntwork-io/terragrunt/releases/download/v0.77.5/terragrunt_linux_amd64
sudo chmod +x /usr/local/bin/terragrunt

echo "Installing yq..."
sudo wget -qO /usr/local/bin/yq \
  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

echo "Installing kubectl..."
KUBECTL_VERSION=$(curl -Ls https://dl.k8s.io/release/stable.txt)
curl -Lo /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl

echo "Installing helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "Installing rclone..."
curl https://rclone.org/install.sh | sudo bash

echo "Installing AWS CLI v2..."
curl -Lo /tmp/awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
unzip -q /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install --update

echo ""
echo "=== Verifying installations ==="
tofu --version
terragrunt --version
yq --version
kubectl version --client
helm version --short
jq --version
rclone --version | head -1
aws --version

echo ""
echo "=== All tools installed successfully ==="

#!/usr/bin/env bash
set -euo pipefail

K3S_VERSION="${K3S_VERSION:-v1.36.5+k3s1}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script with sudo: sudo $0"
  exit 1
fi

export INSTALL_K3S_VERSION="$K3S_VERSION"
curl -sfL https://get.k3s.io | sh -s - server

systemctl enable k3s
systemctl --no-pager --full status k3s --lines=20 || true

KUBE_VERSION="$(/usr/local/bin/k3s --version | awk 'NR==1 {print $3}' | sed 's/+k3s.*//')"
KUBECTL_TMP="$(mktemp)"
trap 'rm -f "$KUBECTL_TMP"' EXIT
curl -fsSL "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/amd64/kubectl" -o "$KUBECTL_TMP"
install -m 0755 "$KUBECTL_TMP" /usr/local/bin/kubectl

install -d -m 0700 /root/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
chmod 0600 /root/.kube/config

if id ubuntu >/dev/null 2>&1; then
  install -d -m 0700 /home/ubuntu/.kube
  cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
  chown -R ubuntu:ubuntu /home/ubuntu/.kube
  chmod 0600 /home/ubuntu/.kube/config
fi

/usr/local/bin/k3s kubectl get nodes -o wide
/usr/local/bin/k3s kubectl get pods -A

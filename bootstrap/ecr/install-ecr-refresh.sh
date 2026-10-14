#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?Set AWS_REGION}"
: "${ECR_REGISTRY:?Set ECR_REGISTRY}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script with sudo."
  exit 1
fi

apt-get update
apt-get install -y awscli

install -d -m 0750 /opt/orderflow
install -d -m 0700 /etc/orderflow
install -m 0750 "$(dirname "$0")/refresh-ecr-pull-secret.sh" /opt/orderflow/refresh-ecr-pull-secret.sh

cat > /etc/orderflow/ecr.env <<ENV
AWS_REGION=${AWS_REGION}
ECR_REGISTRY=${ECR_REGISTRY}
NAMESPACE=orderflow
SECRET_NAME=ecr-registry
ENV
chmod 0600 /etc/orderflow/ecr.env

install -m 0644 "$(dirname "$0")/orderflow-ecr-pull.service" /etc/systemd/system/orderflow-ecr-pull.service
install -m 0644 "$(dirname "$0")/orderflow-ecr-pull.timer" /etc/systemd/system/orderflow-ecr-pull.timer

systemctl daemon-reload
systemctl enable --now orderflow-ecr-pull.timer
systemctl start orderflow-ecr-pull.service

systemctl --no-pager status orderflow-ecr-pull.timer --lines=20

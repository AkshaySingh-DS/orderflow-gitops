#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:?Set AWS_REGION}"
ECR_REGISTRY="${ECR_REGISTRY:?Set ECR_REGISTRY}"
NAMESPACE="${NAMESPACE:-orderflow}"
SECRET_NAME="${SECRET_NAME:-ecr-registry}"

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || \
  kubectl create namespace "$NAMESPACE"

PASSWORD="$(aws ecr get-login-password --region "$AWS_REGION")"

kubectl -n "$NAMESPACE" create secret docker-registry "$SECRET_NAME" \
  --docker-server="$ECR_REGISTRY" \
  --docker-username=AWS \
  --docker-password="$PASSWORD" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

echo "Refreshed ${SECRET_NAME} in namespace ${NAMESPACE}."

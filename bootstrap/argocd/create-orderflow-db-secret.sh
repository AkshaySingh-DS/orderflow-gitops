#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-orderflow}"
SECRET_NAME="${SECRET_NAME:-orderflow-db}"
POSTGRES_USER="${POSTGRES_USER:-orderflow}"
POSTGRES_DB="${POSTGRES_DB:-orderflow}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -hex 16)}"

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || \
  kubectl create namespace "$NAMESPACE"

if kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
  echo "Secret ${SECRET_NAME} already exists; refusing to rotate it automatically."
  exit 0
fi

DATABASE_URL="postgresql+psycopg://${POSTGRES_USER}:${POSTGRES_PASSWORD}@orderflow-postgresql:5432/${POSTGRES_DB}"

kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-literal=POSTGRES_USER="$POSTGRES_USER" \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --from-literal=POSTGRES_DB="$POSTGRES_DB" \
  --from-literal=DATABASE_URL="$DATABASE_URL"

echo "Created ${SECRET_NAME} in namespace ${NAMESPACE}."

#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_OWNER:?Set GITHUB_OWNER to your GitHub owner/org}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

project_tmp="$(mktemp)"
app_tmp="$(mktemp)"
trap 'rm -f "$project_tmp" "$app_tmp"' EXIT

sed "s/REPLACE_WITH_GITHUB_OWNER/${GITHUB_OWNER}/g" \
  "$REPO_ROOT/argocd/project.yaml" > "$project_tmp"

sed "s/REPLACE_WITH_GITHUB_OWNER/${GITHUB_OWNER}/g" \
  "$REPO_ROOT/argocd/application.yaml" > "$app_tmp"

kubectl apply -f "$project_tmp"
kubectl apply -f "$app_tmp"

kubectl -n argocd get appproject orderflow
kubectl -n argocd get application orderflow

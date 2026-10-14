#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_APP_ID:?Set GITHUB_APP_ID}"
: "${GITHUB_APP_INSTALLATION_ID:?Set GITHUB_APP_INSTALLATION_ID}"
: "${GITHUB_APP_PRIVATE_KEY_PATH:?Set GITHUB_APP_PRIVATE_KEY_PATH}"
: "${GITOPS_REPO_URL:?Set GITOPS_REPO_URL}"

PRIVATE_KEY="$(cat "${GITHUB_APP_PRIVATE_KEY_PATH}")"

kubectl -n argocd apply -f - <<MANIFEST
apiVersion: v1
kind: Secret
metadata:
  name: orderflow-gitops-repository
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: ${GITOPS_REPO_URL}
  githubAppID: "${GITHUB_APP_ID}"
  githubAppInstallationID: "${GITHUB_APP_INSTALLATION_ID}"
  githubAppPrivateKey: |
$(printf '%s\n' "$PRIVATE_KEY" | sed 's/^/    /')
MANIFEST

kubectl -n argocd get secret orderflow-gitops-repository

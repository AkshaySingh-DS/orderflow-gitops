#!/usr/bin/env bash
set -euo pipefail

# Register the private platform-config repo with Argo CD using a read-only
# GitHub App. The App installation must have Contents: read on this repo.
: "${GITHUB_OWNER:?Set GITHUB_OWNER}"
: "${GITHUB_APP_ID:?Set numeric GITHUB_APP_ID}"
: "${GITHUB_APP_INSTALLATION_ID:?Set GITHUB_APP_INSTALLATION_ID}"
: "${GITHUB_APP_PRIVATE_KEY_FILE:?Set path to the GitHub App private-key PEM}"
test -r "$GITHUB_APP_PRIVATE_KEY_FILE"

kubectl -n argocd create secret generic orderflow-platform-config-repo \
  --from-literal=type=git \
  --from-literal=url="https://github.com/${GITHUB_OWNER}/orderflow-platform-config.git" \
  --from-literal=githubAppID="$GITHUB_APP_ID" \
  --from-literal=githubAppInstallationID="$GITHUB_APP_INSTALLATION_ID" \
  --from-file=githubAppPrivateKey="$GITHUB_APP_PRIVATE_KEY_FILE" \
  --dry-run=client -o yaml   | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml   | kubectl apply -f -

kubectl apply -f "$(dirname "$0")/root-application.yaml"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SEALED_SECRET="${REPO_ROOT}/secrets/production/secrets.encrypted.yaml"

if [ ! -f "$SEALED_SECRET" ]; then
  echo "Missing sealed secret:"
  echo "$SEALED_SECRET"
  echo ""
  echo "Run ./scripts/make_secrets.sh first."
  exit 1
fi

echo "Bootstrapping ArgoCD..."

kubectl apply -f "${REPO_ROOT}/argocd/application.yaml"

echo ""
echo "GitOps bootstrap started."
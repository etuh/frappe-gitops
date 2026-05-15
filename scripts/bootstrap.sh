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

cd "$(dirname "$0")/.." || exit 1
cp -v secrets/production/secrets.encrypted.yaml overlays/production/secrets.encrypted.yaml

mkdir -p ~/.kube

sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$USER":"$USER" ~/.kube/config
chmod 600 ~/.kube/config

export KUBECONFIG=~/.kube/config

echo "Bootstrapping ArgoCD..."

kubectl apply -f "${REPO_ROOT}/argocd/application.yaml"

echo ""
echo "GitOps bootstrap started."

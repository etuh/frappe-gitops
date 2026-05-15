#!/usr/bin/env bash
set -euo pipefail

#######################################
# Configuration
#######################################

ARGOCD_VERSION="v3.4.2"
ARGOCD_CLI_VERSION="v3.4.2"
CERT_MANAGER_VERSION="v1.20.2"
SEALED_SECRETS_VERSION="v0.26.0"

#######################################
# Install K3s
#######################################

echo "Installing K3s..."

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="\
  --disable=servicelb \
  --write-kubeconfig-mode=600" \
sh -

#######################################
# Configure kubectl
#######################################

mkdir -p ~/.kube

sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$USER":"$USER" ~/.kube/config
chmod 600 ~/.kube/config

export KUBECONFIG=~/.kube/config

kubectl get nodes

#######################################
# Namespaces
#######################################

for ns in argocd cert-manager frappe; do
  kubectl create namespace "$ns" \
    --dry-run=client -o yaml | kubectl apply -f -
done

#######################################
# Install ArgoCD
#######################################

kubectl apply --server-side --force-conflicts \
  -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

kubectl rollout status deployment/argocd-server \
  -n argocd \
  --timeout=300s

#######################################
# Install ArgoCD CLI
#######################################

curl -sSL -o argocd-linux-amd64 \
  "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_CLI_VERSION}/argocd-linux-amd64"

sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd

rm argocd-linux-amd64

#######################################
# Install cert-manager
#######################################

kubectl apply -f \
  "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

kubectl rollout status deployment/cert-manager \
  -n cert-manager \
  --timeout=300s

kubectl rollout status deployment/cert-manager-webhook \
  -n cert-manager \
  --timeout=300s

#######################################
# Install Sealed Secrets
#######################################

kubectl apply -f \
  "https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/controller.yaml"

kubectl rollout status deployment/sealed-secrets-controller \
  -n kube-system \
  --timeout=300s

echo ""
echo "Platform install complete."
echo "Next: run ./secrets/make_secrets.sh"
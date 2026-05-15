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
  --write-kubeconfig-mode=600 \
  --cluster-domain=cluster.local" \
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
# Fix CoreDNS upstream resolvers
#######################################

echo "Waiting for CoreDNS..."

kubectl wait \
  --for=condition=Ready \
  pod \
  -n kube-system \
  -l k8s-app=kube-dns \
  --timeout=180s

until kubectl get configmap coredns -n kube-system >/dev/null 2>&1; do
  sleep 2
done

echo "Patching CoreDNS..."

kubectl patch configmap coredns \
  -n kube-system \
  --type merge \
  -p '{
    "data": {
      "Corefile": ".:53 {\n    errors\n    health\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n      pods insecure\n      fallthrough in-addr.arpa ip6.arpa\n    }\n    prometheus :9153\n    forward . 8.8.8.8 1.1.1.1\n    cache 30\n    loop\n    reload\n    loadbalance\n}"
    }
  }'

kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=180s

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
echo "Next: run ./scripts/make_secrets.sh"
echo "Finally: run ./scripts/bootstrap.sh"
#!/usr/bin/env bash
set -euo pipefail

#######################################
# Configuration
#######################################

REPO_URL="https://github.com/etuh/frappe-gitops.git"

ARGOCD_HOST="argocd.dairyndumberi.local"
FRAPPE_HOST="frappe.dairyndumberi.local"

# Version pinning for reproducible installs

ARGOCD_VERSION="v3.4.2"
ARGOCD_CLI_VERSION="v3.4.2"

CERT_MANAGER_VERSION="v1.20.2"

#######################################
# Install K3s
#######################################

echo "======================================"
echo "Installing K3s (Disable ServiceLB, Keep Traefik)"
echo "======================================"

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="\
  --disable=servicelb \
  --write-kubeconfig-mode=600" \
sh -

#######################################
# Configure kubectl
#######################################

echo "======================================"
echo "Configuring kubectl"
echo "======================================"

mkdir -p ~/.kube

sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$USER":"$USER" ~/.kube/config
chmod 600 ~/.kube/config

export KUBECONFIG=~/.kube/config

kubectl get nodes

#######################################
# Namespaces
#######################################

echo "======================================"
echo "Creating namespaces"
echo "======================================"

for ns in argocd cert-manager frappe; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

#######################################
# Install ArgoCD
#######################################

echo "======================================"
echo "Installing ArgoCD"
echo "======================================"

# kubectl delete crd applicationsets.argoproj.io --ignore-not-found
# could delete existing ApplicationSets if this cluster already had ArgoCD.
# So this is not safe on a production cluster.

kubectl apply --server-side --force-conflicts \
  -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

# For HA:
# -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/ha/install.yaml

kubectl rollout status deployment/argocd-server \
  -n argocd \
  --timeout=300s

#######################################
# Install ArgoCD CLI
#######################################

echo "======================================"
echo "Installing ArgoCD CLI"
echo "======================================"

curl -sSL -o argocd-linux-amd64 \
  "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_CLI_VERSION}/argocd-linux-amd64"

sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd

rm argocd-linux-amd64

#######################################
# Install cert-manager
#######################################

echo "======================================"
echo "Installing cert-manager"
echo "======================================"

kubectl apply -f \
  "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

kubectl rollout status deployment/cert-manager \
  -n cert-manager \
  --timeout=300s

kubectl rollout status deployment/cert-manager-webhook \
  -n cert-manager \
  --timeout=300s

#######################################
# Create local issuer
#######################################

echo "======================================"
echo "Creating self-signed ClusterIssuer"
echo "======================================"

cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: local-selfsigned
spec:
  selfSigned: {}
EOF

#######################################
# Bootstrap GitOps
#######################################

echo "======================================"
echo "Bootstrapping ArgoCD GitOps config"
echo "======================================"

kubectl apply -f argocd/application.yaml

#######################################
# Initial password
#######################################

echo "======================================"
echo "Retrieving ArgoCD admin password"
echo "======================================"

ARGOCD_PASSWORD=$(
  kubectl -n argocd \
    get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d
)

echo ""
echo "ArgoCD initial admin password:"
echo "$ARGOCD_PASSWORD"
echo ""

#######################################
# Hosts configuration
#######################################

echo "======================================"
echo "Hosts file configuration"
echo "======================================"

NODE_IP=$(
  kubectl get nodes \
    -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
)

echo "Add these lines to /etc/hosts:"
echo "$NODE_IP  $ARGOCD_HOST"
echo "$NODE_IP  $FRAPPE_HOST"

echo ""

#######################################
# Complete
#######################################

echo "======================================"
echo "Bootstrap complete"
echo "======================================"

echo "ArgoCD URL: https://$ARGOCD_HOST"
echo "Frappe URL: https://$FRAPPE_HOST"

echo ""
echo "ArgoCD ingress is managed from Git."
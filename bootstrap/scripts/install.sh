#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/etuh/frappe-gitops.git"
ARGOCD_HOST="argocd.dairyndumberi.local"

echo "======================================"
echo "Installing Terraform"
echo "======================================"

sudo apt-get update

sudo apt-get install -y \
  curl \
  gnupg \
  software-properties-common \
  unzip

curl -fsSL https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor \
  -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

. /etc/os-release

# Linux Mint reports VERSION_CODENAME=virginia,
# but HashiCorp repo expects Ubuntu codename.
if [[ -n "${UBUNTU_CODENAME:-}" ]]; then
  OS_CODENAME="$UBUNTU_CODENAME"
else
  OS_CODENAME="$VERSION_CODENAME"
fi

echo \
"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com \
${OS_CODENAME} main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt-get update
sudo apt-get install -y terraform

terraform version

echo "======================================"
echo "Installing K3s (disable Traefik)"
echo "======================================"

curl -sfL https://get.k3s.io | \
INSTALL_K3S_EXEC="--disable traefik --kubelet-arg=eviction-hard=imagefs.available<1%,nodefs.available<1%" sh -

echo "======================================"
echo "Configuring kubectl"
echo "======================================"

mkdir -p ~/.kube

sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

sudo chown "$USER":"$USER" ~/.kube/config

export KUBECONFIG=~/.kube/config

kubectl get nodes

echo "======================================"
echo "Creating namespaces"
echo "======================================"

kubectl create namespace argocd \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create namespace cert-manager \
  --dry-run=client -o yaml | kubectl apply -f -

echo "======================================"
echo "Installing ArgoCD"
echo "======================================"

kubectl apply \
  -n argocd \
  --server-side \
  --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl rollout status \
  deployment/argocd-server \
  -n argocd \
  --timeout=300s

echo "======================================"
echo "Installing ArgoCD CLI"
echo "======================================"

curl -o argocd-linux-amd64 \
https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64

sudo install -m 555 argocd-linux-amd64 \
/usr/local/bin/argocd

rm argocd-linux-amd64

echo "======================================"
echo "Installing cert-manager"
echo "======================================"

kubectl apply -f \
https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

kubectl rollout status \
deployment/cert-manager \
-n cert-manager \
# --timeout=300s
kubectl rollout status \
deployment/cert-manager-webhook \
-n cert-manager \
--timeout=300s
echo "======================================"
echo "Creating local self-signed issuer"
echo "======================================"

cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: local-selfsigned
spec:
  selfSigned: {}
EOF

echo "======================================"
echo "ArgoCD admin password"
echo "======================================"

ARGOCD_PASSWORD=$(
kubectl -n argocd get secret argocd-initial-admin-secret \
-o jsonpath='{.data.password}' | base64 -d
)

echo "$ARGOCD_PASSWORD"

echo "======================================"
echo "Port forwarding ArgoCD"
echo "======================================"

kubectl port-forward \
svc/argocd-server \
-n argocd \
8080:443 >/dev/null 2>&1 &

# sleep 10

echo "======================================"
echo "Logging into ArgoCD"
echo "======================================"

argocd login localhost:8080 \
  --username admin \
  --password "$ARGOCD_PASSWORD" \
  --insecure

echo "======================================"
echo "Registering Git repository"
echo "======================================"

argocd repo add "$REPO_URL"

echo "======================================"
echo "Bootstrapping cluster root app"
echo "======================================"

kubectl apply \
-f clusters/prod/root-app.yaml

echo "======================================"
echo "Bootstrap complete"
echo "======================================"

echo "ArgoCD URL:"
echo "https://${ARGOCD_HOST}"

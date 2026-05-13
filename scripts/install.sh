#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/etuh/frappe-gitops.git"
ARGOCD_HOST="argocd.dairyndumberi.local"

echo "======================================"
echo "Installing K3s (Disable Traefik & ServiceLB)"
echo "======================================"
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="\
  --disable=traefik \
  --disable=servicelb \
  --write-kubeconfig-mode=644" \
sh -

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
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace frappe --dry-run=client -o yaml | kubectl apply -f -

echo "======================================"
echo "Installing ArgoCD (Without Internal TLS)"
echo "======================================"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

echo "======================================"
echo "Installing ArgoCD CLI"
echo "======================================"
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

echo "======================================"
echo "Patching ArgoCD Server for HTTP (No TLS)"
echo "======================================"
kubectl patch deployment argocd-server -n argocd --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--insecure"}]'
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

echo "======================================"
echo "Installing cert-manager (For Self-Signed Ingress)"
echo "======================================"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=300s
kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=300s

echo "======================================"
echo "Creating local self-signed cluster issuer"
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
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
echo "$ARGOCD_PASSWORD"
echo "Login to ArgoCD using this command: argocd login $ARGOCD_HOST --username admin --password $ARGOCD_PASSWORD --insecure"

echo "======================================"
echo "Creating ArgoCD Ingress"
echo "======================================"
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    cert-manager.io/cluster-issuer: local-selfsigned
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  tls:
  - hosts:
    - $ARGOCD_HOST
    secretName: argocd-tls
  rules:
  - host: $ARGOCD_HOST
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF

echo "======================================"
echo "Bootstrapping cluster root app"
echo "======================================"
kubectl apply -f argocd/application.yaml

echo "======================================"
echo "Bootstrap complete"
echo "======================================"
echo "ArgoCD URL: https://${ARGOCD_HOST}"
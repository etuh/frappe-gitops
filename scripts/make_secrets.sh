#!/usr/bin/env bash
set -euo pipefail

#######################################
# Resolve repository root
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

#######################################
# Paths
#######################################

CERT_FILE="${REPO_ROOT}/secrets/sealed-secrets-cert.pem"

PLAIN_SECRET="${REPO_ROOT}/secrets/production/secrets.yaml"

SEALED_SECRET="${REPO_ROOT}/secrets/production/secrets.encrypted.yaml"

#######################################
# Install kubeseal if missing
#######################################

if ! command -v kubeseal >/dev/null 2>&1; then
  echo "kubeseal CLI not found. Installing..."
  # Keeping this version in sync with install.sh
  KUBESEAL_VERSION="v0.26.0"
  
  curl -sL "https://github.com/bitnami-labs/sealed-secrets/releases/download/${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION#v}-linux-amd64.tar.gz" | tar xz kubeseal
  sudo install -m 755 kubeseal /usr/local/bin/kubeseal
  rm kubeseal
  
  echo "kubeseal installed successfully."
  echo ""
fi

#######################################
# Validate input or Prompt
#######################################

if [ ! -f "$PLAIN_SECRET" ]; then
  echo "Missing plaintext secret at $PLAIN_SECRET"
  echo "Creating one now..."
  
  read -s -p "Enter Database root password: " DB_PASS
  echo ""
  read -s -p "Enter Frappe Administrator password: " ADMIN_PASS
  echo ""
  
  mkdir -p "$(dirname "$PLAIN_SECRET")"
  
  cat <<EOF > "$PLAIN_SECRET"
apiVersion: v1
kind: Secret
metadata:
  name: frappe-secrets
  namespace: frappe
type: Opaque
stringData:
  db-password: "${DB_PASS}"
  admin-password: "${ADMIN_PASS}"
EOF

  echo "Plaintext secret file created at $PLAIN_SECRET."
  echo "WARNING: Don't commit the plaintext file!"
fi

#######################################
# Fetch certificate if missing
#######################################

if [ ! -f "$CERT_FILE" ]; then
  echo "Sealed Secrets certificate not found."
  echo "Fetching cluster certificate..."

  # Note: Adjust the controller name and namespace based on your installation if necessary.
  kubeseal --fetch-cert --controller-name sealed-secrets-controller --controller-namespace kube-system > "$CERT_FILE"

  echo "Saved certificate:"
  echo "$CERT_FILE"
fi

#######################################
# Seal secrets
#######################################

echo "Encrypting secrets..."

kubeseal \
  --format yaml \
  --cert "$CERT_FILE" \
  < "$PLAIN_SECRET" \
  > "$SEALED_SECRET"

echo ""
echo "Created:"
echo "$SEALED_SECRET"
echo ""
echo "Commit only the encrypted file to Git."

cp -v secrets/production/secrets.encrypted.yaml overlays/production/secrets.encrypted.yaml
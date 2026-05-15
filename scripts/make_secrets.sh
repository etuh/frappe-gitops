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
# Validate input
#######################################

if [ ! -f "$PLAIN_SECRET" ]; then
  echo "Missing plaintext secret:"
  echo "$PLAIN_SECRET"
  exit 1
fi

#######################################
# Fetch certificate if missing
#######################################

if [ ! -f "$CERT_FILE" ]; then
  echo "Sealed Secrets certificate not found."
  echo "Fetching cluster certificate..."

  kubeseal --fetch-cert > "$CERT_FILE"

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
#!/usr/bin/env bash

set -euo pipefail

# Load environment variables from .env file if it exists
if [ -f .env ]; then
  source .env
fi

# ============================================
# CONFIG
# ============================================
GITHUB_USERNAME="${GITHUB_USERNAME:-etuh}"
# Ensure GITHUB_TOKEN is set in your environment or .env file

FRAPPE_VERSION="v16.17.0"
ERPNEXT_VERSION="v16.17.0"
HRMS_VERSION="v16.6.1"

BUILD_DATE=$(date +%F)

IMAGE_NAME="frappe"
IMAGE_TAG="${BUILD_DATE}"

# Custom full image name pointing to GHCR
FULL_IMAGE_NAME="ghcr.io/${GITHUB_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"

# Ensure we use upstream's prefix if specified (or just let the Dockerfile use 'frappe')
FRAPPE_IMAGE_PREFIX="frappe"

# ============================================
# CREATE apps.json (Base64 for build arg)
# ============================================
echo "Preparing apps config..."
APPS_JSON_BASE64=$(cat << APPS_JSON_EOF | base64 -w 0
[
  {
    "url": "https://github.com/frappe/erpnext",
    "branch": "${ERPNEXT_VERSION}"
  },
  {
    "url": "https://github.com/frappe/hrms",
    "branch": "${HRMS_VERSION}"
  }
]
APPS_JSON_EOF
)

# ============================================
# BUILD IMAGE
# ============================================
echo "Building image ${FULL_IMAGE_NAME}..."

podman build \
  --no-cache \
  --build-arg FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg FRAPPE_BRANCH=${FRAPPE_VERSION} \
  --build-arg FRAPPE_IMAGE_PREFIX=${FRAPPE_IMAGE_PREFIX} \
  --build-arg APPS_JSON_BASE64=${APPS_JSON_BASE64} \
  --tag ${FULL_IMAGE_NAME} \
  --file build/Containerfile \
  .

# ============================================
# LOGIN TO GHCR & PUSH
# ============================================
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "⚠️ GITHUB_TOKEN is not set in the environment or .env file. Skipping GHCR login and push."
  echo "Image was built locally as ${FULL_IMAGE_NAME}."
  exit 0
fi

echo "Logging into GHCR..."
echo "${GITHUB_TOKEN}" | podman login ghcr.io \
  -u "${GITHUB_USERNAME}" \
  --password-stdin

echo "Pushing image to GHCR..."
podman push ${FULL_IMAGE_NAME}

echo ""
echo "========================================"
echo "SUCCESS!"
echo "Image pushed:"
echo "${FULL_IMAGE_NAME}"
echo "========================================"

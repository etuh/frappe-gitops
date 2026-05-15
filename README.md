# Frappe GitOps Setup

This repository contains a production-oriented Kubernetes deployment for Frappe (ERPNext + HRMS) using GitOps principles with Argo CD.

It includes:

- Custom Frappe container builds
- Kubernetes manifests managed with Kustomize
- Automated GitOps deployments
- Secret encryption using Sealed Secrets
- Automated cluster bootstrapping using K3s

---

# 🚀 Architecture

This deployment consists of the following layers:

### Data Layer

- MariaDB (StatefulSet + PVC)
- Redis Cache
- Redis Queue

### Application Layer

- Frappe Backend (Gunicorn)
- Frappe Websocket (SocketIO)
- Frappe Workers
  - Short Worker
  - Long Worker
  - Scheduler Worker

### Edge Layer

- Nginx
- Kubernetes Ingress
- TLS certificates via cert-manager

### Platform Layer

- Argo CD
- Kustomize
- Sealed Secrets
- K3s

---

# 📁 Repository Structure

```text
.
├── argocd/
│   ├── application.yaml
│   └── ingress.yaml
│
├── base/
│   ├── backend/
│   ├── mariadb/
│   ├── redis/
│   ├── workers/
│   ├── websocket/
│   ├── nginx/
│   ├── site-init-job.yaml
│   └── kustomization.yaml
│
├── overlays/
│   └── production/
│       ├── patch-replicas.yaml
│       └── kustomization.yaml
│
├── secrets/
│   ├── sealed-secrets-cert.pem
│   └── production/
│       ├── secrets.yaml
│       └── secrets.encrypted.yaml
│
├── scripts/
│   ├── install.sh
│   ├── make_secrets.sh
│   └── bootstrap.sh
│
└── build/
```

---

# Prerequisites

Before bootstrapping, ensure the following are installed locally:

- `kubectl`
- `kubeseal`
- `git`
- `curl`
- `podman` or `docker` (for image builds)
- `sudo` access on the target server

Optional but recommended:

- `jq`
- `yq`

---

# 🔐 Secret Management

This project uses Sealed Secrets.

Only encrypted secrets are committed to Git.

## Local secret file

Create:

```text
secrets/production/secrets.yaml
```

Example:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: frappe-secrets
  namespace: frappe
type: Opaque
stringData:
  db-password: your-db-password
  admin-password: your-admin-password
```

This file is ignored by Git.

`secrets/production/secrets.yaml` is a local operator file and must never be committed to Git or stored on production servers.

---

# ☸️ First-Time Cluster Setup

## Step 1 — Install platform components

Run:

```bash
./scripts/install.sh
```

This installs:

- K3s
- ArgoCD
- cert-manager
- Sealed Secrets Controller

This script does **not** deploy Frappe yet.

---

## Step 2 — Encrypt secrets

Run:

```bash
./scripts/make_secrets.sh
```

This script:

- fetches the Sealed Secrets public certificate (if missing)
- stores it at:

```text
secrets/sealed-secrets-cert.pem
```

- encrypts:

```text
secrets/production/secrets.yaml
```

into:

```text
secrets/production/secrets.encrypted.yaml
```

The certificate is cluster-specific and normally only needs to be fetched once per cluster.

Commit the encrypted secret:

```bash
git add secrets/production/secrets.encrypted.yaml
git commit -m "Add production secrets"
git push
```

---

## Step 3 — Bootstrap GitOps deployment

Run:

```bash
./scripts/bootstrap.sh
```

This:

- verifies encrypted secrets exist
- creates the ArgoCD Application
- starts GitOps sync

---

# GitOps Deployment Flow

```text
Infrastructure
↓
Secrets
↓
Application Bootstrap
↓
ArgoCD Sync
↓
Frappe Deployment
```

---

# Updating Secrets

To rotate or update credentials:

1. Update:

```text
secrets/production/secrets.yaml
```

2. Re-encrypt:

```bash
./scripts/make_secrets.sh
```

3. Commit and push:

```bash
git add secrets/production/secrets.encrypted.yaml
git commit -m "Rotate production secrets"
git push
```

ArgoCD will automatically sync the updated secret.

---

# Site Initialization

The site initialization job is defined in:

```text
base/site-init-job.yaml
```

This job:

- waits for MariaDB readiness
- creates the site if missing
- runs database migrations

Because site data is stored in persistent volumes, site initialization only happens when needed.

Your site data survives:

- pod restarts
- ArgoCD syncs
- rolling updates

---

# Scaling

Production replica counts are managed in:

```text
overlays/production/patch-replicas.yaml
```

Example:

- Backend: 3 replicas
- Workers: configurable independently

---

# Storage Requirements

The shared `frappe-sites` volume requires:

```text
ReadWriteMany (RWX)
```

Supported storage backends include:

- NFS
- CephFS
- EFS

Update:

```text
base/pvc.yaml
```

to match your cluster storage class.

---

# Database Strategy

Current architecture runs:

- MariaDB inside cluster
- Redis inside cluster

This is suitable for:

- single-node production
- small team deployments
- edge / on-prem environments

For larger deployments, you may move MariaDB or Redis to dedicated infrastructure or use managed services.

---

# Ingress

ArgoCD ingress is managed in:

```text
argocd/ingress.yaml
```

Application ingress is managed in:

```text
base/nginx/ingress.yaml
```

Default domains:

```text
argocd.dairyndumberi.local
frappe.dairyndumberi.local
```

Add them to `/etc/hosts` or your internal DNS.

---

# Building Custom Images

To build your custom Frappe image:

```bash
./build/build.sh
```

Push the image to your registry before production deployment.

---

# Backup Strategy

Backups run via:

```text
base/backup-cronjob.yaml
```

Current command:

```bash
bench --site frappe.dairyndumberi.local backup --with-files
```

For production, ship backups to external object storage such as S3, Google Cloud Storage, or Azure Blob Storage.

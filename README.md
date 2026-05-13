# Frappe GitOps Setup

This repository contains a complete, minimal, production-ready Kubernetes setup for deploying Frappe (ERPNext + HRMS) using GitOps principles and **ArgoCD**. It includes configurations for generating a custom Frappe Docker image with specific applications pre-installed and deploying all necessary services.

## 🚀 Architecture

The cluster runs the following Frappe components:

- **MariaDB** (Database + PVC)
- **Redis Cache & Redis Queue** (Caching and Background Jobs)
- **Frappe Backend** (Gunicorn)
- **Frappe Websocket** (Node.js SocketIO for realtime events)
- **Frappe Workers** (Short queues, Long queues, and Scheduled jobs)
- **Nginx** (Reverse proxy + Static Assets)
- **Init Configurator** (Sidecar pattern that automatically generates `common_site_config.json`)
- **Site-Init PreSync Job** (Automatically bootstraps sites dynamically)

All Frappe pods (Backend, Workers, Nginx) share a single `ReadWriteMany` Persistent Volume Claim (`frappe-sites`) storing site assets and logs.

## 📁 Repository Structure

```text
.
├── argocd/                # ArgoCD Application manifest
├── base/                  # Base Kubernetes manifests (Deployments, Services, PV, PVC, Secrets)
├── build/                 # Scripts and Containerfile for building the custom docker image
└── overlays/
    └── production/        # Environment-specific patches (e.g., replicas, specialized tags)
```

## 🛠️ Building the Custom Image

The project packages apps directly into the Docker image at build time (rather than dynamically at runtime) to ensure determinism and scalability.

To build the image locally:

```bash
./build/build.sh
```

This runs `podman build` constructing the `custom-frappe:v16.17.0` image containing `erpnext` and `hrms`.

> _Note: Before deploying to a cloud-based Kubernetes cluster, you must tag and push this image to a Docker registry your cluster can access, then update the image references in the `base/` manifests._

## ☸️ Deployment via ArgoCD

1. **Secure your Secrets**: Do not commit plaintext secrets. Use a GitOps-compatible secret manager such as Sealed Secrets or External Secrets. This repo includes templates only.
2. **Apply the Application Configuration**:
   Apply the ArgoCD `Application` resource, which points to the `overlays/production` directory of this repo.

   ```bash
   kubectl apply -f argocd/application.yaml
   ```

3. **Automation Check**:
   When ArgoCD performs a sync, it will first execute the `PreSync` job located in `base/site-init-job.yaml`. This ensures the site (`frappe.dairyndumberi.local`) is created and DB schemas are migrated properly before starting the backend deployments.

## ⚙️ Configuration Adjustments

- **Site Name**: You can customize your site's name by updating the `SITE_NAME` environment variable within `base/backend/deployment.yaml` and `base/site-init-job.yaml`.
- **Replicas**: You can scale workloads by updating the replica counts either in the base files or in Kustomize patches (e.g., `overlays/production/patch-replicas.yaml`).
- **Storage**: By default, `base/pvc.yaml` requests `10Gi` via default storage class. Make sure your cluster's StorageClass supports `ReadWriteMany` (RWX) access modes (like NFS or EFS).

## Secret Management (Required)

This repo ships only templates:

- `base/secrets.example.yaml` (plaintext example, never commit real values)
- `base/secrets.encrypted.yaml` (SealedSecret shape, placeholder only)

Use one of these approaches:

- **Sealed Secrets**: create a sealed secret and include only the encrypted manifest in Git.
- **External Secrets Operator**: sync secrets from a cloud secrets manager.
- **ArgoCD Vault Plugin**: render secrets at deploy time from a vault backend.

If you are using Sealed Secrets:

1. Create a Secret manifest from the example (or use `kubectl create secret`).
2. Seal it and save to your overlay:

   ```bash
   kubeseal --format yaml < base/secrets.example.yaml > overlays/production/secrets.encrypted.yaml
   ```

3. Add `overlays/production/secrets.encrypted.yaml` to `overlays/production/kustomization.yaml`.

The secret must be named `frappe-secrets` and include keys `db-password` and `admin-password`.

### Sealed Secrets Controller Prerequisite

The cluster must have the Bitnami Sealed Secrets controller installed before syncing this application. Without the controller, `SealedSecret` resources will not be decrypted into Kubernetes `Secret` objects.

## Storage Requirements (RWX)

The shared `frappe-sites` PVC uses `ReadWriteMany`. Your cluster must provide an RWX-capable StorageClass (NFS, CephFS, EFS, etc.). This repo defaults to `storageClassName: rwx-storage-class` in `base/pvc.yaml`; set it to the RWX class name available in your cluster.

## Ingress (Local Network)

The base manifests include an Ingress at `base/nginx/ingress.yaml` for `frappe.dairyndumberi.local` **without TLS** (plain HTTP).

Ensure:

- An Ingress controller (e.g., NGINX Ingress) is installed in your cluster.
- `frappe.dairyndumberi.local` resolves to your Ingress controller’s external IP (add to `/etc/hosts` or configure local DNS).

## Backup Strategy

A daily backup CronJob is included at `base/backup-cronjob.yaml` and runs:

```bash
bench --site frappe.dairyndumberi.local backup --with-files
```

This stores backups in the sites volume. For durable disaster recovery, ship generated backup files to external storage (S3, Azure Blob, GCS, or NFS).

## 🚀 First-time Cluster Setup

If you are bootstrapping a completely new server (or local VM), a utility script is provided to automate installing K3s, ArgoCD, and bootstrapping this repository immediately to the cluster.

To execute the setup, run:

```bash
./scripts/install.sh
```

Ensure your `scripts/install.sh` points to your GitHub Repository URL prior to running it.

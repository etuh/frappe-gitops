# Frappe GitOps

This repository is the GitOps source of truth for a production K3s cluster running
Frappe with Argo CD, cert-manager, and supporting services. It uses the app-of-apps
pattern with Argo CD as the single point of control for all cluster state.

---

## Repository structure

```
frappe-gitops/
├── bootstrap/
│   ├── terraform/
│   │   ├── main.tf
│   │   ├── providers.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── scripts/
│       └── install.sh
├── clusters/
│   ├── dev/
│   │   ├── root-app.yaml
│   │   └── namespaces.yaml
│   ├── staging/
│   │   ├── root-app.yaml
│   │   └── namespaces.yaml
│   └── prod/
│       ├── root-app.yaml
│       └── namespaces.yaml
├── infrastructure/
│   ├── cert-manager/
│   │   ├── kustomization.yaml
│   │   └── namespace.yaml
│   ├── ingress/
│   │   ├── kustomization.yaml
│   │   └── namespace.yaml
│   ├── storage/
│   │   ├── kustomization.yaml
│   │   └── namespace.yaml
│   └── monitoring/
│       ├── kustomization.yaml
│       └── namespace.yaml
├── platform/
│   ├── mariadb/
│   │   ├── kustomization.yaml
│   │   └── namespace.yaml
│   ├── redis/
│   │   ├── kustomization.yaml
│   │   └── namespace.yaml
│   └── secrets/
│       ├── kustomization.yaml
│       └── namespace.yaml
└── apps/
    ├── frappe/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   ├── ingress.yaml
    │   ├── pvc.yaml
    │   ├── migrate-job.yaml
    │   └── kustomization.yaml
    └── argocd/
        ├── project.yaml
        ├── applications.yaml
        └── argocd-ingress.yaml
```

---

## Key design decisions

- **K3s cluster**: Traefik is disabled; NGINX ingress controller is expected.
- **Immutable images**: Always use specific tags (e.g., `v16.0.3`), never `latest`.
- **App-of-apps**: Root app in `clusters/prod/root-app.yaml` syncs all infrastructure,
  platform, and app workloads via `apps/argocd/applications.yaml`.
- **Self-signed TLS**: Uses `local-selfsigned` ClusterIssuer for `.local` domains.
- **Deterministic rollbacks**: Image tags ensure rollback reliability.
- **Migration hooks**: `migrate-job.yaml` is a PreSync hook that runs before deployment.
- **Multi-environment ready**: `clusters/dev`, `clusters/staging`, `clusters/prod`.

---

## Bootstrap and initial setup

### Prerequisites

- A Linux node (Debian/Ubuntu) with sudo access.
- Git access to https://github.com/etuh/frappe-gitops.git
- Internet access for package downloads.

### Install

1. Clone the repository:

   ```bash
   git clone https://github.com/etuh/frappe-gitops.git
   cd frappe-gitops
   ```

2. Run the bootstrap script:

   ```bash
   ./bootstrap/scripts/install.sh
   ```

   This script:
   - Installs Terraform (optional, for future IaC).
   - Installs K3s with Traefik disabled.
   - Installs Argo CD and the Argo CD CLI.
   - Installs cert-manager and creates a self-signed ClusterIssuer.
   - Registers this Git repository with Argo CD.
   - Applies the root app to bootstrap the cluster.

3. After bootstrap, install an ingress controller:

   ```bash
   kubectl create namespace ingress-nginx
   helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
   helm install ingress-nginx ingress-nginx/ingress-nginx \
     -n ingress-nginx \
     --set controller.service.type=NodePort \
     --set controller.service.nodePorts.http=80 \
     --set controller.service.nodePorts.https=443
   ```

4. Configure DNS or `/etc/hosts`:

   ```
   <your-k3s-node-ip> argocd.dairyndumberi.local frappe.example.com
   ```

   Update `frappe.example.com` to your internal domain.

5. Access Argo CD:

   ```
   https://argocd.dairyndumberi.local
   ```

   The admin password is printed by the bootstrap script.

---

## Argo CD app-of-apps architecture

The root application (`clusters/prod/root-app.yaml`) manages everything:

```
root-app (Argo CD manages this)
  ├── argocd (manages the ArgoCD project and all child apps)
  │   ├── cert-manager
  │   ├── ingress
  │   ├── storage
  │   ├── monitoring
  │   ├── mariadb
  │   ├── redis
  │   ├── secrets
  │   └── frappe
```

**Why this matters**:

- Argo CD is self-managed; it syncs its own definitions.
- All infrastructure is declarative and version-controlled.
- Rollback any change by reverting Git commits.

---

## Updating Frappe to a new image

Frappe updates are managed via Git commits that change the image tag in
`apps/frappe/deployment.yaml`.

### Workflow

1. **Build a new Frappe image** (in your build pipeline, not in this repo):

   ```bash
   docker build -t ghcr.io/etuh/frappe:v16.0.5 .
   docker push ghcr.io/etuh/frappe:v16.0.5
   ```

2. **Update the deployment in this repo**:

   ```bash
   cd frappe-gitops
   ```

   Edit `apps/frappe/deployment.yaml` and change the image tag:

   ```yaml
   # Before
   image: ghcr.io/etuh/frappe:2026-05-08

   # After
   image: ghcr.io/etuh/frappe:v16.0.5
   ```

   Also update `apps/frappe/migrate-job.yaml` with the same tag:

   ```yaml
   # Before
   image: ghcr.io/etuh/frappe:2026-05-08

   # After
   image: ghcr.io/etuh/frappe:v16.0.5
   ```

3. **Commit and push**:

   ```bash
   git add apps/frappe/
   git commit -m "frappe: bump image to v16.0.5"
   git push origin main
   ```

4. **Argo CD syncs automatically** (or manually):
   - Argo CD detects the change in Git within seconds.
   - The `migrate-job.yaml` (PreSync hook) runs first to execute `bench migrate`.
   - Then the new deployment rolls out.
   - Old pods are gracefully terminated.

5. **Verify the rollout**:

   ```bash
   kubectl rollout status deployment/frappe -n frappe
   kubectl get pods -n frappe
   ```

### Rollback

To roll back to a previous image:

1. Find the commit with the old tag:

   ```bash
   git log --oneline apps/frappe/deployment.yaml
   ```

2. Revert the commit:

   ```bash
   git revert <commit-hash>
   git push origin main
   ```

3. Argo CD automatically syncs the rollback. Migrations are idempotent, so
   running them again is safe.

---

## Secrets management

Currently, no secrets are committed. To deploy credentials:

1. **Create a Secret in the cluster manually** (temporary, for bootstrap):

   ```bash
   kubectl create secret generic frappe-secrets \
     --from-literal=MYSQL_PASSWORD=<password> \
     --from-literal=REDIS_PASSWORD=<password> \
     -n frappe
   ```

2. **For production, use one of**:
   - **Sealed Secrets**: Commit encrypted secrets to Git.
   - **External Secrets Operator**: Reference external vaults (e.g., AWS Secrets Manager).
   - **HashiCorp Vault**: Self-hosted secrets backend.

   These go in `platform/secrets/`. Choose one and implement in production.

---

## Environment separation

Each environment has its own root app:

### Dev

```bash
kubectl apply -f clusters/dev/root-app.yaml
```

### Staging

```bash
kubectl apply -f clusters/staging/root-app.yaml
```

### Production

```bash
kubectl apply -f clusters/prod/root-app.yaml
```

To use environment-specific overrides (e.g., different replica counts, resource
limits), add `kustomization.yaml` overlays in each environment.

---

## Operations

### Monitor Argo CD applications

```bash
argocd app list
argocd app status <app-name>
argocd app sync <app-name>
argocd app diff <app-name>
```

### Manual sync

```bash
argocd app sync root-app
```

### Check Frappe deployment status

```bash
kubectl get deployment frappe -n frappe
kubectl logs -n frappe -l app=frappe --tail=100
```

### View migration job logs

```bash
kubectl logs -n frappe -l app=frappe,job-name=frappe-migrate
```

### Scale Frappe replicas

Edit `apps/frappe/deployment.yaml`:

```yaml
spec:
  replicas: 3 # Change from 2
```

Commit and push. Argo CD will scale up.

---

## Multi-environment strategy

If running multiple clusters (dev, staging, prod):

1. Create separate Git branches or subdirectories for each environment.
2. Point each cluster's root app to its respective path:

   ```yaml
   # dev/root-app.yaml
   path: apps/argocd
   ```

   ```yaml
   # staging/root-app.yaml
   path: apps/argocd
   ```

   ```yaml
   # prod/root-app.yaml
   path: apps/argocd
   ```

3. Add per-environment overlays:

   ```
   apps/frappe/overlays/dev/
   apps/frappe/overlays/staging/
   apps/frappe/overlays/prod/
   ```

---

## Next steps

- [ ] Replace `frappe.example.com` with your internal domain in `apps/frappe/ingress.yaml`.
- [ ] Implement a secrets solution under `platform/secrets/`.
- [ ] Add MariaDB and Redis manifests under `platform/mariadb/` and `platform/redis/`.
- [ ] Add monitoring (Prometheus, Grafana) under `infrastructure/monitoring/`.
- [ ] Test disaster recovery: delete a node and verify automatic recovery.

---

## What makes this production-ready

1. **App-of-apps**: Single source of truth; GitOps controls everything.
2. **Image tags**: Deterministic rollbacks; never `latest`.
3. **Migration hooks**: Schema upgrades run before deployment.
4. **Multi-environment**: Dev, staging, prod separation.
5. **Self-healing**: Argo CD auto-syncs; failed deployments are reconciled.
6. **Audit trail**: Every change is a Git commit.

---

## References

- [Argo CD documentation](https://argo-cd.readthedocs.io/)
- [GitOps best practices](https://github.com/weaveworks/awesome-gitops)
- [K3s documentation](https://docs.k3s.io/)
- [cert-manager documentation](https://cert-manager.io/)

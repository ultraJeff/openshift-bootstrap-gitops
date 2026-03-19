# OpenShift Bootstrap GitOps Repository

This repository contains standardized configurations for bootstrapping new OpenShift clusters with common operational settings, managed via ArgoCD.

## Structure

```
├── applications/               # ArgoCD Application manifests
│   ├── developer-hub.yaml      # RHDH (requires manual secrets first)
│   ├── keycloak.yaml           # Keycloak (requires manual secrets first)
│   ├── networking.yaml         # Network Observability (NetObserv + Loki)
│   ├── observability.yaml      # Cluster Observability (external repo)
│   ├── orchestrator.yaml       # Serverless + Serverless Logic operators
│   ├── security.yaml           # OAuth, htpasswd, admin RBAC
│   ├── storage.yaml            # LVM Storage + Image Registry
│   └── resource-test-app/      # Sample test application
├── cluster-configs/            # Cluster-level Kustomize configurations
│   ├── acm/                    # Advanced Cluster Management
│   ├── acs/                    # Red Hat Advanced Cluster Security
│   ├── developer-hub/          # Red Hat Developer Hub (Backstage)
│   │   └── secrets/            # Manual secrets (not in GitOps)
│   ├── gitops/                 # OpenShift GitOps (ArgoCD instance)
│   ├── keycloak/               # Keycloak (RHBK)
│   │   └── secrets/            # Manual secrets (not in GitOps)
│   ├── networking/             # NetObserv, Loki, MinIO
│   ├── orchestrator/           # Serverless + Serverless Logic operators
│   ├── security/               # htpasswd OAuth, admin RBAC
│   └── storage/                # LVM Storage, StorageClass, Image Registry
└── infrastructure/             # Install-time and node configurations
    ├── compact-cluster/        # Assisted Installer configs (install-config, agent-config)
    ├── disk-partitioning/      # SNO disk layout (install-time only)
    └── node-configs/           # Kubelet log rotation, journald, image GC
```

## Quick Start

### Option A: Bootstrap Everything (New Cluster)
```bash
# Deploy all cluster configurations
oc apply -k cluster-configs/

# Apply manual secrets (required before ArgoCD sync)
oc apply -k cluster-configs/developer-hub/secrets/
oc apply -k cluster-configs/keycloak/secrets/

# Register ArgoCD Applications
oc apply -k applications/
```

### Option B: Deploy Components Individually
```bash
# 1. Storage (deploy first — other components depend on it)
oc apply -k cluster-configs/storage/

# 2. OpenShift GitOps (ArgoCD)
oc apply -k cluster-configs/gitops/

# 3. Security (OAuth, admin user)
oc apply -k cluster-configs/security/

# 4. Platform operators
oc apply -k cluster-configs/networking/
oc apply -k cluster-configs/orchestrator/
oc apply -k cluster-configs/acm/
oc apply -k cluster-configs/acs/

# 5. Applications (apply secrets first!)
oc apply -k cluster-configs/keycloak/secrets/
oc apply -k cluster-configs/keycloak/

oc apply -k cluster-configs/developer-hub/secrets/
oc apply -k cluster-configs/developer-hub/
```

### Monitor Deployment
```bash
# Operator status
oc get subscriptions -A
oc get csv -A

# Storage
oc get lvmcluster -n openshift-storage
oc get pvc -n openshift-image-registry

# GitOps
oc get argocd -n openshift-gitops
oc get applications -n openshift-gitops

# RHDH
oc get backstage -n rhdh
oc get pods -n rhdh
```

## ArgoCD Applications

| Application | Source | Secrets Required |
|-------------|--------|-----------------|
| `developer-hub` | `cluster-configs/developer-hub` | Yes — `oc apply -k cluster-configs/developer-hub/secrets/` |
| `keycloak` | `cluster-configs/keycloak` | Yes — `oc apply -k cluster-configs/keycloak/secrets/` |
| `networking` | `cluster-configs/networking` | No (MinIO creds in minio-secrets.yaml) |
| `observability` | External: `ultraJeff/cluster-o11y-operator-demo` | No |
| `orchestrator` | `cluster-configs/orchestrator` | No |
| `security` | `cluster-configs/security` | No |
| `storage` | `cluster-configs/storage` | No |

The observability stack is managed in a separate repository ([cluster-o11y-operator-demo](https://github.com/ultraJeff/cluster-o11y-operator-demo)) and deployed via ArgoCD Application referencing that external repo.

## External Repositories

- **[cluster-o11y-operator-demo](https://github.com/ultraJeff/cluster-o11y-operator-demo)** — Cluster Observability Operator, LokiStack, TempoStack, monitoring, tracing, and UI plugins. Deployed as an ArgoCD Application from `applications/observability.yaml`.

## Single Node OpenShift (SNO) Disk Partitioning

**Must be done during installation only.**

1. Customize `infrastructure/disk-partitioning/98-create-a-partition-for-lvmstorage.yaml`
2. Upload the MachineConfig via Assisted Installer
3. After installation, apply storage configs:
```bash
oc apply -k cluster-configs/storage/
```

See `infrastructure/compact-cluster/README.md` for detailed instructions.

## Related Documentation

- [RHDH Migration Plan](RHDH-MIGRATION-PLAN.md) — Feature parity checklist between clusters
- [WARP.md](WARP.md) — Warp terminal reference guide

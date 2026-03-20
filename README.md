# OpenShift Bootstrap GitOps Repository

This repository contains standardized configurations for bootstrapping new OpenShift clusters with common operational settings, managed via ArgoCD.

## Structure

```
├── applications/               # ArgoCD Application manifests
│   ├── developer-hub.yaml      # RHDH (requires manual secrets first)
│   ├── keycloak.yaml           # Keycloak (requires manual secrets first)
│   ├── observability.yaml      # Cluster Observability (external repo)
│   ├── network-observability.yaml # Network Observability (external repo)
│   ├── external-secrets.yaml   # External Secrets Operator (external repo)
│   ├── rhoai.yaml              # Red Hat OpenShift AI (external repo)
│   ├── service-mesh.yaml       # OpenShift Service Mesh 3 (external repo)
│   ├── keda.yaml               # KEDA Autoscaling (external repo)
│   ├── orchestrator.yaml       # Serverless + Serverless Logic operators
│   ├── security.yaml           # OAuth, htpasswd, admin RBAC
│   └── storage.yaml            # LVM Storage + Image Registry
├── cluster-configs/            # Cluster-level Kustomize configurations
│   ├── acm/                    # Advanced Cluster Management
│   ├── acs/                    # Red Hat Advanced Cluster Security
│   ├── developer-hub/          # Red Hat Developer Hub (Backstage)
│   │   └── secrets/            # Manual secrets (not in GitOps)
│   ├── gitops/                 # OpenShift GitOps (ArgoCD instance)
│   ├── keycloak/               # Keycloak (RHBK)
│   │   └── secrets/            # Manual secrets (not in GitOps)
│   ├── orchestrator/           # Serverless + Serverless Logic operators
│   ├── security/               # htpasswd OAuth, admin RBAC
│   └── storage/                # LVM Storage, StorageClass, Image Registry
├── demos/                      # Demo applications (not deployed via ArgoCD)
│   └── resource-test-app/      # Sample resource test application
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
# 1. Storage (deploy first -- other components depend on it)
oc apply -k cluster-configs/storage/

# 2. OpenShift GitOps (ArgoCD)
oc apply -k cluster-configs/gitops/

# 3. Security (OAuth, admin user)
oc apply -k cluster-configs/security/

# 4. Platform operators
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

### In-Repo Components

| Application | Source | Secrets Required |
|-------------|--------|-----------------|
| `developer-hub` | `cluster-configs/developer-hub` | Yes |
| `keycloak` | `cluster-configs/keycloak` | Yes |
| `orchestrator` | `cluster-configs/orchestrator` | No |
| `security` | `cluster-configs/security` | No |
| `storage` | `cluster-configs/storage` | No |

### External Repos

| Application | Repo | Path | Depends On |
|-------------|------|------|------------|
| `observability` | [cluster-o11y-operator-demo](https://github.com/ultraJeff/cluster-o11y-operator-demo) | `observability` | -- |
| `network-observability` | [network-o11y-operator-demo](https://github.com/ultraJeff/network-o11y-operator-demo) | `overlays/integrated` | observability (shared MinIO + Loki) |
| `external-secrets` | [eso-demo](https://github.com/ultraJeff/eso-demo) | `.` | -- |
| `rhoai` | [rhoai-super-slim](https://github.com/ultraJeff/rhoai-super-slim) | `manifests/base` | -- |
| `service-mesh` | [ossm-3-demo](https://github.com/ultraJeff/ossm-3-demo) | `deploy/overlays/integrated` | observability (shared MinIO + operators) |
| `keda` | [microservices-keda](https://github.com/ultraJeff/microservices-keda) | `infrastructure` | -- |

External repos use a base/overlay pattern. The `integrated` overlay shares infrastructure (MinIO, operators) deployed by the `observability` app. Each repo also provides a `standalone` overlay for independent deployment.

## Shared Infrastructure

The `observability` app (cluster-o11y-operator-demo) deploys shared infrastructure used by other apps:

- **MinIO** (in `minio` namespace) -- S3-compatible storage for Loki and Tempo
- **Loki Operator** -- log storage for logging and network observability
- **Tempo Operator** -- trace storage for observability and service mesh
- **OTel Operator** -- telemetry collection
- **COO** -- Cluster Observability Operator with UI plugins

The `network-observability` and `service-mesh` apps use `integrated` overlays that reference this shared infrastructure instead of deploying their own copies.

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

- [RHDH Migration Plan](RHDH-MIGRATION-PLAN.md) -- Feature parity checklist between clusters

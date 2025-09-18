# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Repository Overview

This is an OpenShift Bootstrap GitOps repository containing standardized configurations for bootstrapping new OpenShift clusters with common operational settings. It uses Kustomize for configuration management and follows GitOps principles for cluster configuration deployment.

## Architecture

### Repository Structure
- **cluster-configs/**: Main cluster configurations organized by component
  - **storage/**: LVM Storage Operator, LVMCluster, and Image Registry storage
  - **gitops/**: OpenShift GitOps (ArgoCD) operator installation
  - **acm/**: Advanced Cluster Management operator and MultiClusterHub
  - **logging/**: Log retention policies for kubelet and journald
  - **security/**: RBAC configurations and security policies
  - **developer-hub/**: Red Hat Developer Hub (Backstage) configurations
- **infrastructure/**: Infrastructure components (installation-time only)
  - **disk-partitioning/**: SNO disk partitioning configs for install-time use
- **applications/**: (Future) Application deployment configurations

### Configuration Management
- Uses **Kustomize** for configuration composition and overlay management
- Each component has its own `kustomization.yaml` with resources and common labels
- Main `cluster-configs/kustomization.yaml` orchestrates all component deployments
- Common labels applied: `config.openshift.io/bootstrap: "true"` and `config.openshift.io/managed-by: gitops`
- Component-specific labels (e.g., `config.openshift.io/component: storage`) for resource organization

### Component Architecture Details

**LVM Storage Configuration**:
- `lvmstorage-operator.yaml`: Operator subscription and namespace
- `lvmcluster.yaml`: Defines storage class with thin provisioning (90% pool, 10x overprovisioning)
- `image-registry-storage.yaml`: Configures persistent storage for internal registry
- Dependency: Requires `/dev/disk/by-partlabel/lvmstorage` partition

**GitOps Configuration**:
- `gitops-operator.yaml`: Installs OpenShift GitOps operator
- ArgoCD instance created automatically in `openshift-gitops` namespace

**ACM Configuration**:
- `multiclusterhub.yaml`: Configures ACM with high availability and selective component enablement
- Includes governance, search, application lifecycle, and cluster lifecycle management

**Red Hat Developer Hub (RHDH) Configuration**:
- `rhdh-instance.yaml`: Complete RHDH deployment including Backstage CR, Secret, and ConfigMap
- Uses external ConfigMap approach for app configuration (more reliable than rawRuntimeConfig)
- Configures guest authentication for development environments
- Includes static authentication token for API access
- Environment variables provided via Secret for security

### Deployment Dependencies
Storage must be deployed first (LVM Storage), followed by other components. The system is designed to work with Single Node OpenShift (SNO) clusters that require disk partitioning during installation.

## Common Commands

### Cluster Bootstrap Commands

```bash
# Bootstrap entire cluster with all components
oc apply -k cluster-configs/

# Deploy components individually (recommended order)
oc apply -k cluster-configs/storage/     # Deploy first
oc apply -k cluster-configs/gitops/
oc apply -k cluster-configs/acm/
oc apply -k cluster-configs/logging/
oc apply -k cluster-configs/security/
oc apply -k cluster-configs/developer-hub/
```

### Verification Commands

```bash
# Check storage components
oc get lvmcluster -n openshift-storage
oc get storageclass
oc get pvc -n openshift-image-registry

# Check GitOps
oc get argocd -n openshift-gitops
oc get subscription -n openshift-gitops-operator

# Check ACM
oc get multiclusterhub -n open-cluster-management
oc get subscription -n open-cluster-management

# Check RHDH
oc get backstage -n rhdh
oc get pods -n rhdh
oc get route -n rhdh

# Check all operators
oc get subscriptions -A
oc get csv -A
```

### Troubleshooting Commands

```bash
# Storage troubleshooting
oc describe lvmcluster -n openshift-storage
oc get lvmvolumegroupnodestatus -n openshift-storage
oc logs -n openshift-storage -l app=lvms-operator

# Registry troubleshooting
oc get config.imageregistry.operator.openshift.io/cluster -o yaml
oc get pods -n openshift-image-registry

# RHDH troubleshooting
oc logs -n rhdh -l rhdh.redhat.com/app=backstage-developer-hub
oc get configmap -n rhdh backstage-appconfig-developer-hub -o yaml
oc get secret -n rhdh my-rhdh-secrets -o yaml
oc get route -n rhdh

# Log retention verification
oc debug node/NODE_NAME -- chroot /host journalctl --disk-usage
oc debug node/NODE_NAME -- chroot /host find /var/log/pods -name "*.log.*" -mtime +7
```

### Single Node OpenShift (SNO) Disk Partitioning

For SNO clusters, disk partitioning must be configured during installation:

```bash
# Verify partition exists (post-installation)
ls -la /dev/disk/by-partlabel/lvmstorage

# Check disk layout
lsblk

# Post-installation storage setup
oc apply -f cluster-configs/storage/lvmstorage-operator.yaml
oc apply -f cluster-configs/storage/lvmcluster.yaml
```

### Emergency Log Cleanup Commands

```bash
# Force container log cleanup
oc debug node/NODE_NAME -- chroot /host find /var/log/pods -name "*.log.*" -mtime +7 -delete

# Vacuum journal logs
oc debug node/NODE_NAME -- chroot /host journalctl --vacuum-time=7d
```

## Development Guidelines

### Working with Kustomize Configurations

When modifying configurations:
1. Edit component-specific YAML files in their respective directories
2. Update `kustomization.yaml` files when adding/removing resources
3. Test with `oc kustomize cluster-configs/` to verify YAML generation
4. Apply to test cluster before committing changes

### OpenShift Context Requirements

This repository requires:
- OpenShift CLI (`oc`) installed and authenticated as cluster-admin
- Target OpenShift cluster (4.12+ recommended)
- For SNO: Proper disk partitioning completed during installation

### Configuration Customization

- **Storage sizes**: Edit `cluster-configs/storage/image-registry-storage.yaml`
- **Log retention**: Modify values in `cluster-configs/logging/` YAML files
- **ACM components**: Update `cluster-configs/acm/multiclusterhub.yaml`
- **Device paths**: For SNO, ensure `infrastructure/disk-partitioning/` configs match your hardware

### Testing Changes

Before applying to production clusters:
1. Use `oc kustomize` to preview generated YAML
2. Apply to development/test cluster first
3. Verify operator installations with `oc get csv -A`
4. Test storage provisioning with test PVCs

### Kustomize Development Commands

```bash
# Preview generated YAML for entire bootstrap
oc kustomize cluster-configs/

# Preview specific component YAML
oc kustomize cluster-configs/storage/
oc kustomize cluster-configs/gitops/
oc kustomize cluster-configs/acm/

# Validate YAML structure without applying
oc kustomize cluster-configs/ | oc apply --dry-run=client -f -

# Show differences between current and proposed configs
oc diff -k cluster-configs/
```

### Butane Configuration Development

For modifying disk partitioning configurations:

```bash
# Convert Butane template to MachineConfig
butane infrastructure/disk-partitioning/create-partition-for-lvmstorage.bu -o infrastructure/disk-partitioning/98-create-a-partition-for-lvmstorage.yaml

# Validate Butane syntax
butane --check infrastructure/disk-partitioning/create-partition-for-lvmstorage.bu

# Preview Butane output without writing file
butane infrastructure/disk-partitioning/create-partition-for-lvmstorage.bu
```

## Important Notes

- **Disk partitioning configurations** in `infrastructure/disk-partitioning/` can ONLY be applied during OpenShift installation
- **Storage components** must be deployed before other components that may require persistent storage
- **The OpenShift server URL** for this environment is: https://api.tallgeese.ultra.lab:6443
- **Log retention policies** require node reboots when applied via MachineConfig
- **ACM and GitOps operators** may take several minutes to fully deploy and become ready

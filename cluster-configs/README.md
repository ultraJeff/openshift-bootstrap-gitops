# OpenShift Cluster Bootstrap Configurations

This directory contains YAML manifests to bootstrap a new OpenShift cluster with essential operators and configurations.

## Prerequisites

1. **Disk Partitioning**: Ensure you have created the LVM storage partition during installation using the Butane configuration in `../infrastructure/disk-partitioning/`

2. **OpenShift CLI**: Make sure `oc` is installed and you're logged in as cluster-admin

## Components Included

### Storage (`storage/`)
- **LVM Storage Operator**: Provides dynamic storage provisioning using local volumes
- **LVMCluster**: Configures LVM with thin provisioning on `/dev/disk/by-partlabel/lvmstorage`
- **StorageClass**: Default storage class `lvms-lvmstorage` for persistent volumes
- **Image Registry Storage**: Configures OpenShift's internal image registry with persistent storage

### GitOps (`gitops/`)
- **OpenShift GitOps Operator**: Installs ArgoCD for GitOps workflows
- **ArgoCD Instance**: Default ArgoCD instance is automatically created

### Advanced Cluster Management (`acm/`)
- **ACM Operator**: Installs Red Hat Advanced Cluster Management
- **MultiClusterHub**: Configures ACM with essential components enabled

### Logging (`logging/`)
- **Log Retention Policies**: Configures kubelet and journald log rotation

### Keycloak (`keycloak/`)
- **Red Hat build of Keycloak Operator**: Installs the Keycloak operator
- **Keycloak Instance**: Deploys Keycloak with PostgreSQL database
- **RHDH Client Configuration**: Includes pre-configured OIDC client for Red Hat Developer Hub integration

## Deployment Instructions

### Option 1: Deploy Everything at Once
```bash
oc apply -k cluster-configs/
```

### Option 2: Deploy Components Individually

1. **Storage (deploy first)**:
```bash
oc apply -k cluster-configs/storage/
```

2. **Wait for LVM Storage to be ready** (check that the LVMCluster is ready):
```bash
oc get lvmcluster -n openshift-storage
```

3. **GitOps**:
```bash
oc apply -k cluster-configs/gitops/
```

4. **ACM**:
```bash
oc apply -k cluster-configs/acm/
```

5. **Logging**:
```bash
oc apply -k cluster-configs/logging/
```

6. **Keycloak**:
```bash
oc apply -k cluster-configs/keycloak/
```

## Post-Deployment Verification

### Check Storage
```bash
# Verify LVM Storage
oc get lvmcluster -n openshift-storage
oc get storageclass

# Verify Image Registry
oc get pvc -n openshift-image-registry
oc get config.imageregistry.operator.openshift.io/cluster
```

### Check GitOps
```bash
# Verify GitOps Operator
oc get subscription -n openshift-gitops-operator

# Check ArgoCD instance
oc get argocd -n openshift-gitops
```

### Check ACM
```bash
# Verify ACM Operator
oc get subscription -n open-cluster-management

# Check MultiClusterHub
oc get multiclusterhub -n open-cluster-management
```

### Check Keycloak
```bash
# Verify Keycloak Operator
oc get subscription.operators.coreos.com -n keycloak

# Check Keycloak instance
oc get keycloak -n keycloak

# Verify all Keycloak resources
oc get pods,statefulset,route -n keycloak

# Get admin credentials
oc get secret keycloak-initial-admin -n keycloak -o jsonpath='{.data.username}' | base64 -d && echo
oc get secret keycloak-initial-admin -n keycloak -o jsonpath='{.data.password}' | base64 -d && echo
```

## Access URLs

After deployment, you can access:

- **ArgoCD**: `https://openshift-gitops-server-openshift-gitops.apps.<cluster-domain>`
- **ACM Console**: Available through the OpenShift Console under "All Clusters"
- **Keycloak**: Get the URL with `oc get route -n keycloak`

### Keycloak RHDH Client Configuration

To integrate Keycloak with Red Hat Developer Hub:

1. Log into Keycloak admin console using the credentials from `keycloak-initial-admin` secret
2. Create a new realm or use the master realm
3. Import the OIDC client configuration:
   - Navigate to **Clients** > **Import client**
   - Select the file `cluster-configs/keycloak/rhdh.json`
   - Update the `redirectUris` and `webOrigins` to match your RHDH instance URL
   - Note the client secret for configuring RHDH

## Customization

### Storage Size
Edit `cluster-configs/storage/image-registry-storage.yaml` to adjust the registry PVC size (default: 100Gi).

### ACM Components
Edit `cluster-configs/acm/multiclusterhub.yaml` to enable/disable specific ACM components.

### Storage Class
Edit `cluster-configs/storage/lvmcluster.yaml` to modify the storage class configuration or create additional storage classes.

## Troubleshooting

### Storage Issues
1. Ensure the partition `/dev/disk/by-partlabel/lvmstorage` exists on your nodes
2. Check LVMCluster status: `oc describe lvmcluster -n openshift-storage`
3. Verify device detection: `oc get lvmvolumegroupnodestatus -n openshift-storage`

### Image Registry Issues
1. Check if the registry PVC is bound: `oc get pvc -n openshift-image-registry`
2. Verify registry pods are running: `oc get pods -n openshift-image-registry`
3. Check registry configuration: `oc get config.imageregistry.operator.openshift.io/cluster -o yaml`

### Operator Issues
1. Check subscription status: `oc get subscriptions -A`
2. Verify CSV status: `oc get csv -A`
3. Check operator logs: `oc logs -n <operator-namespace> <operator-pod>`

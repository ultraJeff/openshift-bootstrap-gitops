# Red Hat Advanced Cluster Security (ACS/RHACS) Configuration

This directory contains the configuration files for deploying Red Hat Advanced Cluster Security for Kubernetes (RHACS) on OpenShift clusters.

## Components

### 1. ACS Operator (`acs-operator.yaml`)
- Creates the `rhacs-operator` namespace
- Installs the Red Hat Advanced Cluster Security Operator via OLM
- Uses the `stable` channel with automatic updates

### 2. Stackrox Namespace (`stackrox-namespace.yaml`)
- Creates the `stackrox` namespace where the Central CR runs
- As per Red Hat documentation, Central must run in a separate namespace from the operator

### 3. Central Configuration (`acs-central.yaml`)
- **Single Node OpenShift (SNO) Optimized Configuration**
- Reduced resource requirements for resource-constrained environments:
  - Central: 500m CPU / 2Gi RAM (vs official 1.5 CPU / 4Gi RAM)
  - Scanner: 200m CPU / 1Gi RAM (vs official 1.2 CPU / 2.7Gi RAM)
  - Scanner V4 disabled to reduce resource consumption
  - Autoscaling disabled, single scanner replica
- Exposes Central via OpenShift Route
- Uses 100Gi persistent storage as recommended

### 4. SecuredCluster Configuration (`acs-secured-cluster.yaml`)
- **SNO-Optimized SecuredCluster Configuration** for monitoring the local cluster
- Reduced resource requirements:
  - Sensor: 200m CPU / 500Mi RAM (vs official 1 CPU / 1Gi RAM)
  - Admission Controller: 50m CPU / 100Mi RAM (vs official 50m CPU / 100Mi RAM)
  - Collector: 50m CPU / 320Mi RAM (vs official 50m CPU / 320Mi RAM)
- Uses eBPF collection method for better performance
- Single replica admission controller
- Configures Central endpoint as internal service for same-cluster deployment
- Scanner disabled on secured cluster (uses Central's scanner instead)

### 5. Deployment Script (`deploy-secured-cluster.sh`)
- Automated script to deploy SecuredCluster with proper init bundle
- Handles API token creation, init bundle generation, and deployment

## Resource Requirements

### SNO-Optimized (Current Configuration)
**Central Services:**
- **Total CPU Request**: 700m (Central: 500m + Scanner: 200m)
- **Total Memory Request**: 3Gi (Central: 2Gi + Scanner: 1Gi)
- **Storage**: 100Gi persistent volume

**SecuredCluster Services (when deployed):**
- **Additional CPU Request**: 300m (Sensor: 200m + Admission: 50m + Collector: 50m)
- **Additional Memory Request**: 920Mi (Sensor: 500Mi + Admission: 100Mi + Collector: 320Mi)
- **Total Combined**: ~1000m CPU / ~4Gi RAM
- **Suitable for**: Single Node OpenShift, resource-constrained environments

### Official Red Hat Requirements
For production environments with sufficient resources, consider the official requirements:
- **Central**: 1.5 CPU / 4Gi RAM (Request), 4 CPU / 8Gi RAM (Limit)
- **Scanner**: 1.2 CPU / 2.7Gi RAM (Request), 5 CPU / 8Gi RAM (Limit)
- **Storage**: 100Gi persistent volume

## Deployment

Deploy ACS as part of the full cluster bootstrap:
```bash
oc apply -k cluster-configs/
```

Or deploy ACS Central individually:
```bash
oc apply -k cluster-configs/acs/
```

### Deploy SecuredCluster (Monitoring)

After Central is running, deploy the SecuredCluster to monitor the local cluster:

```bash
# Wait for Central to be fully ready
oc wait --for=condition=Deployed central/stackrox-central-services -n stackrox --timeout=300s

# Run the automated deployment script
./cluster-configs/acs/deploy-secured-cluster.sh
```

Or manually (requires roxctl CLI):
```bash
# Generate init bundle
roxctl -e "https://$(oc get route central -n stackrox -o jsonpath='{.status.ingress[0].host}')" \
  -p "$(oc -n stackrox get secret central-htpasswd -o go-template='{{index .data "password" | base64decode}}')" \
  central init-bundles generate tallgeese-init-bundle \
  --output-secrets /tmp/cluster-init-bundle.yaml

# Apply init bundle and SecuredCluster
oc apply -f /tmp/cluster-init-bundle.yaml -n stackrox
oc apply -f cluster-configs/acs/acs-secured-cluster.yaml
```

## Post-Installation

1. **Get the admin password**:
   ```bash
   oc -n stackrox get secret central-htpasswd -o go-template='{{index .data "password" | base64decode}}'
   ```

2. **Get the Central route**:
   ```bash
   oc -n stackrox get route central -o jsonpath="{.status.ingress[0].host}"
   ```

3. **Access the RHACS Console**: Navigate to the route URL and login with username `admin` and the retrieved password.

## Configuration Notes

- This configuration disables Scanner V4 to reduce resource consumption
- Autoscaling is disabled for predictable resource usage
- Scanner is limited to a single replica for SNO compatibility
- Route-based exposure is used (typical for OpenShift)

## Troubleshooting

Check pod status:
```bash
oc get pods -n rhacs-operator
oc get pods -n stackrox
```

Check Central status:
```bash
oc get central -n stackrox
oc describe central stackrox-central-services -n stackrox
```

## References

- [Red Hat ACS Documentation](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes)
- [OpenShift Bootstrap GitOps Repository](https://github.com/your-repo/openshift-bootstrap-gitops)

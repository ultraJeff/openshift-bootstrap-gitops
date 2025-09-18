# Manual SecuredCluster Deployment

If you don't have `roxctl` CLI available, you can deploy the SecuredCluster manually using the ACS web console.

## Steps

### 1. Access ACS Central Console

```bash
# Get the route URL
oc get route central -n stackrox -o jsonpath="https://{.status.ingress[0].host}"

# Get the admin password
oc -n stackrox get secret central-htpasswd -o go-template='{{index .data "password" | base64decode}}'
```

Login with username `admin` and the retrieved password.

### 2. Generate Init Bundle via Web Console

1. Navigate to **Platform Configuration** → **Integrations**
2. Scroll to **Authentication Tokens** section
3. Click **Cluster Init Bundle**
4. Click **Generate bundle**
5. Enter bundle name: `tallgeese-init-bundle`
6. Click **Generate**
7. Click **Download Kubernetes Secret File** to download the YAML

### 3. Apply Init Bundle

```bash
# Apply the downloaded init bundle
oc apply -f ~/Downloads/tallgeese-init-bundle.yaml -n stackrox
```

### 4. Deploy SecuredCluster

```bash
# Deploy the SecuredCluster CR
oc apply -f cluster-configs/acs/acs-secured-cluster.yaml
```

### 5. Verify Deployment

```bash
# Check SecuredCluster status
oc get securedcluster -n stackrox

# Check all pods
oc get pods -n stackrox

# Wait for all components to be ready
oc wait --for=condition=ready pod -l app.kubernetes.io/name=stackrox -n stackrox --timeout=300s
```

## Expected Pods After Full Deployment

After both Central and SecuredCluster are deployed, you should see:

**Central Services:**
- `central-*` - Main ACS Central service
- `central-db-*` - PostgreSQL database
- `scanner-*` - Image vulnerability scanner
- `scanner-db-*` - Scanner database
- `config-controller-*` - Configuration controller

**SecuredCluster Services:**
- `sensor-*` - Cluster monitoring sensor
- `admission-control-*` - Policy enforcement webhook
- `collector-*` - Runtime data collection (DaemonSet on each node)

## Troubleshooting

If SecuredCluster fails to deploy:

1. **Check Central is ready:**
   ```bash
   oc get central stackrox-central-services -n stackrox -o yaml
   ```

2. **Verify init bundle secrets:**
   ```bash
   oc get secrets -n stackrox | grep -E "(sensor|collector|admission)"
   ```

3. **Check SecuredCluster status:**
   ```bash
   oc describe securedcluster local-cluster -n stackrox
   ```

4. **Monitor pod logs:**
   ```bash
   oc logs -l app=sensor -n stackrox
   oc logs -l app=admission-control -n stackrox
   ```

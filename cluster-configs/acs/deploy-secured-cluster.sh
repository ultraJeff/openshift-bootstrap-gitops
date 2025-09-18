#!/bin/bash
#
# Deploy ACS SecuredCluster for monitoring the local cluster
#
# This script:
# 1. Waits for Central to be ready
# 2. Gets the admin password
# 3. Creates an API token
# 4. Generates an init bundle
# 5. Applies the init bundle secrets
# 6. Deploys the SecuredCluster CR

set -e

NAMESPACE="stackrox"
CLUSTER_NAME="tallgeese"
CENTRAL_ROUTE=$(oc get route central -n ${NAMESPACE} -o jsonpath='{.status.ingress[0].host}')
CENTRAL_URL="https://${CENTRAL_ROUTE}"

echo "🔧 ACS SecuredCluster Deployment Script"
echo "========================================"
echo "Cluster: ${CLUSTER_NAME}"
echo "Central URL: ${CENTRAL_URL}"
echo "Namespace: ${NAMESPACE}"
echo ""

# Wait for Central to be ready
echo "⏳ Waiting for Central to be ready..."
oc wait --for=condition=Deployed central/stackrox-central-services -n ${NAMESPACE} --timeout=300s

# Get admin password
echo "🔑 Retrieving admin password..."
ADMIN_PASSWORD=$(oc -n ${NAMESPACE} get secret central-htpasswd -o go-template='{{index .data "password" | base64decode}}')

# Check if roxctl is available
if ! command -v roxctl &> /dev/null; then
    echo "❌ roxctl CLI not found. Please install roxctl first."
    echo "   You can download it from: https://mirror.openshift.com/pub/rhacs/assets/latest/bin/"
    exit 1
fi

# Set environment variables for roxctl
echo "🔑 Setting up authentication..."
export ROX_CENTRAL_ADDRESS="${CENTRAL_URL}"
export ROX_ADMIN_PASSWORD="${ADMIN_PASSWORD}"

# Generate init bundle
echo "📦 Generating init bundle..."
roxctl -e "${CENTRAL_URL}" --insecure-skip-tls-verify central init-bundles generate "${CLUSTER_NAME}-init-bundle" \
    --output-secrets /tmp/cluster-init-bundle.yaml

# Apply init bundle
echo "🚀 Applying init bundle secrets..."
oc apply -f /tmp/cluster-init-bundle.yaml -n ${NAMESPACE}

# Deploy SecuredCluster
echo "🛡️  Deploying SecuredCluster..."
oc apply -f cluster-configs/acs/acs-secured-cluster.yaml

echo ""
echo "✅ ACS SecuredCluster deployment complete!"
echo "   Monitor status with: oc get securedcluster -n ${NAMESPACE}"
echo "   Check pods with: oc get pods -n ${NAMESPACE}"

# Clean up temporary files
rm -f /tmp/cluster-init-bundle.yaml

echo "🧹 Cleanup complete."

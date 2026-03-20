#!/bin/bash
#
# Cluster Teardown Script — "Pilot Light" Mode
#
# Scales down workloads and removes PDB-blocking resources so the cluster
# can safely perform rolling node reboots (MachineConfig updates, upgrades, etc.).
#
# What stays running:
#   - OpenShift GitOps (ArgoCD) + all Application CRs (for restore)
#   - LVM Storage operator
#   - Core platform operators
#
# Restore with: ./restore.sh
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Preflight check
if ! oc whoami &>/dev/null; then
    error "Not logged into an OpenShift cluster. Aborting."
    exit 1
fi

CLUSTER=$(oc whoami --show-server 2>/dev/null)
echo ""
echo "============================================"
echo "  Cluster Teardown — Pilot Light Mode"
echo "============================================"
echo "  Cluster: ${CLUSTER}"
echo "  User:    $(oc whoami)"
echo "  Date:    $(date)"
echo "============================================"
echo ""
warn "This will scale down all workloads and demo apps."
warn "GitOps and ArgoCD Applications will be preserved for restore."
echo ""
read -p "Continue? (yes/no): " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""

# -----------------------------------------------
# 1. Disable ArgoCD auto-sync on all applications
# -----------------------------------------------
info "Disabling auto-sync on all ArgoCD Applications..."
for app in $(oc get applications -n openshift-gitops -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    if oc get application "$app" -n openshift-gitops -o jsonpath='{.spec.syncPolicy.automated}' 2>/dev/null | grep -q '{'; then
        info "  Removing auto-sync from: $app"
        oc patch application "$app" -n openshift-gitops --type json \
            -p '[{"op": "remove", "path": "/spec/syncPolicy/automated"}]' 2>/dev/null || true
    fi
done

# -----------------------------------------------
# 2. Remove KServe InferenceServices (heaviest workloads)
# -----------------------------------------------
info "Removing KServe InferenceServices..."
for ns in $(oc get inferenceservice --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | sort -u); do
    for isvc in $(oc get inferenceservice -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        info "  Deleting InferenceService: $ns/$isvc"
        oc delete inferenceservice "$isvc" -n "$ns" --wait=false 2>/dev/null || true
    done
done

# -----------------------------------------------
# 3. Scale down RHOAI components
# -----------------------------------------------
info "Scaling down RHOAI operator and components..."
oc scale deployment rhods-operator -n redhat-ods-operator --replicas=0 2>/dev/null || true
for deploy in $(oc get deployments -n redhat-ods-applications -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    oc scale deployment "$deploy" -n redhat-ods-applications --replicas=0 2>/dev/null || true
done

# -----------------------------------------------
# 4. Remove observability workloads (Loki PDBs block drains)
# -----------------------------------------------
info "Scaling down observability stack..."

# Delete LokiStack (removes single-replica PDBs that block node drains)
oc delete lokistack logging-loki -n openshift-logging --wait=false 2>/dev/null || true

# Scale down logging operator so it doesn't recreate resources
oc scale deployment cluster-logging-operator -n openshift-logging --replicas=0 2>/dev/null || true

# Scale down Tempo
for sts in $(oc get statefulsets -n observability -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    oc scale statefulset "$sts" -n observability --replicas=0 2>/dev/null || true
done
for deploy in $(oc get deployments -n observability -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    oc scale deployment "$deploy" -n observability --replicas=0 2>/dev/null || true
done

# Scale down MinIO
oc scale deployment minio -n minio --replicas=0 2>/dev/null || true

# Scale down cluster observability operator
oc scale deployment -n openshift-cluster-observability-operator --all --replicas=0 2>/dev/null || true

# Scale down loki/tempo/otel operators
for ns in openshift-operators openshift-operators-redhat; do
    for deploy in $(oc get deployments -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        oc scale deployment "$deploy" -n "$ns" --replicas=0 2>/dev/null || true
    done
done

# -----------------------------------------------
# 5. Scale down demo applications
# -----------------------------------------------
info "Scaling down demo applications..."
DEMO_NAMESPACES="hotrod-demo quarkus-otel-demo super-slim-demo"
for ns in ${DEMO_NAMESPACES}; do
    for deploy in $(oc get deployments -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        oc scale deployment "$deploy" -n "$ns" --replicas=0 2>/dev/null || true
    done
    for sts in $(oc get statefulsets -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        oc scale statefulset "$sts" -n "$ns" --replicas=0 2>/dev/null || true
    done
done

# -----------------------------------------------
# 6. Scale down RHDH and Keycloak
# -----------------------------------------------
info "Scaling down Developer Hub..."
oc scale deployment backstage-developer-hub -n rhdh --replicas=0 2>/dev/null || true
oc scale statefulset backstage-psql-developer-hub -n rhdh --replicas=0 2>/dev/null || true
oc scale deployment -n rhdh-operator --all --replicas=0 2>/dev/null || true

info "Scaling down Keycloak..."
oc scale statefulset keycloak -n keycloak --replicas=0 2>/dev/null || true
oc scale statefulset postgresql-db -n keycloak --replicas=0 2>/dev/null || true
oc scale deployment rhbk-operator -n keycloak --replicas=0 2>/dev/null || true

# -----------------------------------------------
# 7. Scale down External Secrets operator
# -----------------------------------------------
info "Scaling down External Secrets operator..."
oc scale deployment -n external-secrets-operator --all --replicas=0 2>/dev/null || true

# -----------------------------------------------
# 8. Clean up any remaining PDBs that block drains
# -----------------------------------------------
info "Checking for remaining PDBs with zero disruptions allowed..."
oc get pdb --all-namespaces -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for pdb in data.get('items', []):
    allowed = pdb.get('status', {}).get('disruptionsAllowed', 1)
    if allowed == 0:
        ns = pdb['metadata']['namespace']
        name = pdb['metadata']['name']
        print(f'  WARNING: {ns}/{name} still has 0 disruptions allowed')
" 2>/dev/null

# -----------------------------------------------
# Done
# -----------------------------------------------
echo ""
info "============================================"
info "  Teardown complete — Pilot Light Mode"
info "============================================"
info ""
info "Still running:"
info "  - OpenShift GitOps (ArgoCD)"
info "  - ArgoCD Applications (preserved for restore)"
info "  - LVM Storage operator"
info "  - Core platform operators"
info ""
info "You can now safely:"
info "  - Apply MachineConfig changes (node reboots)"
info "  - Perform cluster upgrades"
info "  - Run maintenance tasks"
info ""
info "To restore: ./restore.sh"

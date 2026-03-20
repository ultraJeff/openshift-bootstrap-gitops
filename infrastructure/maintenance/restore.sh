#!/bin/bash
#
# Cluster Restore Script — Bring back from Pilot Light
#
# Restores all workloads after maintenance by re-scaling operators
# and syncing ArgoCD Applications.
#
# Counterpart to: ./teardown.sh
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
echo "  Cluster Restore — From Pilot Light"
echo "============================================"
echo "  Cluster: ${CLUSTER}"
echo "  User:    $(oc whoami)"
echo "  Date:    $(date)"
echo "============================================"
echo ""
read -p "Restore all workloads? (yes/no): " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""

# -----------------------------------------------
# 1. Restore operators first (they manage their workloads)
# -----------------------------------------------
info "Restoring operators..."

info "  RHOAI operator..."
oc scale deployment rhods-operator -n redhat-ods-operator --replicas=3 2>/dev/null || true

info "  External Secrets operator..."
oc scale deployment -n external-secrets-operator --all --replicas=1 2>/dev/null || true

info "  RHDH operator..."
# Find the operator deployment and scale it back
for deploy in $(oc get deployments -n rhdh-operator -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    oc scale deployment "$deploy" -n rhdh-operator --replicas=1 2>/dev/null || true
done

info "  Keycloak operator..."
oc scale deployment rhbk-operator -n keycloak --replicas=1 2>/dev/null || true

info "  Observability operators..."
oc scale deployment -n openshift-cluster-observability-operator --all --replicas=1 2>/dev/null || true
for ns in openshift-operators openshift-operators-redhat; do
    for deploy in $(oc get deployments -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        oc scale deployment "$deploy" -n "$ns" --replicas=1 2>/dev/null || true
    done
done
oc scale deployment cluster-logging-operator -n openshift-logging --replicas=1 2>/dev/null || true

info "Waiting 30s for operators to reconcile..."
sleep 30

# -----------------------------------------------
# 2. Restore infrastructure workloads
# -----------------------------------------------
info "Restoring Keycloak..."
oc scale statefulset postgresql-db -n keycloak --replicas=1 2>/dev/null || true
sleep 10
oc scale statefulset keycloak -n keycloak --replicas=1 2>/dev/null || true

info "Restoring MinIO..."
oc scale deployment minio -n minio --replicas=1 2>/dev/null || true

info "Restoring Developer Hub..."
oc scale statefulset backstage-psql-developer-hub -n rhdh --replicas=1 2>/dev/null || true
sleep 10
oc scale deployment backstage-developer-hub -n rhdh --replicas=1 2>/dev/null || true

# -----------------------------------------------
# 3. Sync ArgoCD Applications
# -----------------------------------------------
info "Syncing ArgoCD Applications..."
echo ""

APPS=$(oc get applications -n openshift-gitops -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
for app in ${APPS}; do
    info "  Syncing: $app"
    # Use oc to trigger a sync via annotation (works without argocd CLI)
    oc annotate application "$app" -n openshift-gitops \
        argocd.argoproj.io/refresh=normal --overwrite 2>/dev/null || true
done

echo ""
warn "ArgoCD Applications have been refreshed."
warn "Resources deleted during teardown (InferenceServices, LokiStack)"
warn "will be recreated on the next ArgoCD sync."
echo ""
info "To fully sync an app:  oc patch application <name> -n openshift-gitops --type merge -p '{\"operation\":{\"initiatedBy\":{\"username\":\"admin\"},\"sync\":{}}}'"
echo ""

# -----------------------------------------------
# 4. Post-restore checks
# -----------------------------------------------
info "Waiting 30s for workloads to start..."
sleep 30

echo ""
info "=== Post-Restore Status ==="
echo ""
info "Nodes:"
oc get nodes 2>/dev/null
echo ""
info "Problem pods:"
PROBLEMS=$(oc get pods --all-namespaces --field-selector='status.phase!=Running,status.phase!=Succeeded' --no-headers 2>/dev/null | grep -v Completed | head -20)
if [[ -z "${PROBLEMS}" ]]; then
    info "  None — all pods healthy"
else
    echo "${PROBLEMS}"
fi

echo ""
info "PDBs at limit:"
oc get pdb --all-namespaces -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
found = False
for pdb in data.get('items', []):
    allowed = pdb.get('status', {}).get('disruptionsAllowed', 1)
    if allowed == 0:
        ns = pdb['metadata']['namespace']
        name = pdb['metadata']['name']
        print(f'  {ns}/{name}')
        found = True
if not found:
    print('  None — all PDBs allow disruptions')
" 2>/dev/null

echo ""
info "ArgoCD Applications:"
oc get applications -n openshift-gitops -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' --no-headers 2>/dev/null

echo ""
info "============================================"
info "  Restore complete"
info "============================================"
info ""
info "Note: RHOAI dashboard was previously scaled to 1 replica."
info "The operator should reconcile component deployments."
info "InferenceServices will need an ArgoCD sync or manual re-apply."

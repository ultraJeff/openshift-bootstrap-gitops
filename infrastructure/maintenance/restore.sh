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

SKIP_CONFIRM=false
[[ "${1:-}" == "-y" ]] && SKIP_CONFIRM=true

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
if [[ "$SKIP_CONFIRM" != "true" ]]; then
    read -p "Restore all workloads? (yes/no): " CONFIRM
    if [[ "${CONFIRM}" != "yes" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo ""

# -----------------------------------------------
# 1. Restore operators first (they manage their workloads)
# -----------------------------------------------
info "Restoring operators..."

info "  Operators in openshift-operators..."
for deploy in $(oc get deployments -n openshift-operators -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    CURRENT=$(oc get deployment "$deploy" -n openshift-operators -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [[ "$CURRENT" == "0" ]]; then
        oc scale deployment "$deploy" -n openshift-operators --replicas=1 2>/dev/null || true
    fi
done

info "  RHOAI operator..."
oc scale deployment rhods-operator -n redhat-ods-operator --replicas=3 2>/dev/null || true

info "  External Secrets operator..."
oc scale deployment -n external-secrets-operator --all --replicas=1 2>/dev/null || true

info "  RHDH operator..."
for deploy in $(oc get deployments -n rhdh-operator -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    oc scale deployment "$deploy" -n rhdh-operator --replicas=1 2>/dev/null || true
done

info "  Cluster observability operator..."
oc scale deployment -n openshift-cluster-observability-operator --all --replicas=1 2>/dev/null || true

info "Waiting 30s for operators to reconcile..."
sleep 30

# -----------------------------------------------
# 2. Restore observability stack
# -----------------------------------------------
info "Restoring MinIO..."
oc scale deployment minio -n minio --replicas=1 2>/dev/null || true
sleep 5

info "Restoring observability namespace..."
for deploy in $(oc get deployments -n observability -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    CURRENT=$(oc get deployment "$deploy" -n observability -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [[ "$CURRENT" == "0" ]]; then
        oc scale deployment "$deploy" -n observability --replicas=1 2>/dev/null || true
    fi
done
for sts in $(oc get statefulsets -n observability -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    CURRENT=$(oc get statefulset "$sts" -n observability -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [[ "$CURRENT" == "0" ]]; then
        oc scale statefulset "$sts" -n observability --replicas=1 2>/dev/null || true
    fi
done

info "Restoring tracing-system namespace..."
for deploy in $(oc get deployments -n tracing-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    CURRENT=$(oc get deployment "$deploy" -n tracing-system -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [[ "$CURRENT" == "0" ]]; then
        oc scale deployment "$deploy" -n tracing-system --replicas=1 2>/dev/null || true
    fi
done
for sts in $(oc get statefulsets -n tracing-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    CURRENT=$(oc get statefulset "$sts" -n tracing-system -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [[ "$CURRENT" == "0" ]]; then
        oc scale statefulset "$sts" -n tracing-system --replicas=1 2>/dev/null || true
    fi
done

info "Restoring OpenTelemetry collector..."
oc scale deployment -n opentelemetrycollector --all --replicas=1 2>/dev/null || true

info "Restoring COO service mesh monitoring..."
for sts in $(oc get statefulsets -n coo-service-mesh -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    CURRENT=$(oc get statefulset "$sts" -n coo-service-mesh -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [[ "$CURRENT" == "0" ]]; then
        oc scale statefulset "$sts" -n coo-service-mesh --replicas=1 2>/dev/null || true
    fi
done

# -----------------------------------------------
# 3. Restore service mesh
# -----------------------------------------------
info "Restoring service mesh..."
for deploy in $(oc get deployments -n istio-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    CURRENT=$(oc get deployment "$deploy" -n istio-system -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [[ "$CURRENT" == "0" ]]; then
        oc scale deployment "$deploy" -n istio-system --replicas=1 2>/dev/null || true
    fi
done
oc scale deployment -n istio-ingress --all --replicas=1 2>/dev/null || true

# -----------------------------------------------
# 4. Restore infrastructure workloads
# -----------------------------------------------
info "Restoring Developer Hub..."
oc scale statefulset backstage-psql-developer-hub -n rhdh --replicas=1 2>/dev/null || true
sleep 10
oc scale deployment backstage-developer-hub -n rhdh --replicas=1 2>/dev/null || true

# -----------------------------------------------
# 5. Restore RHOAI components and workloads
# -----------------------------------------------
info "Restoring RHOAI components..."
for deploy in $(oc get deployments -n redhat-ods-applications -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    CURRENT=$(oc get deployment "$deploy" -n redhat-ods-applications -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [[ "$CURRENT" == "0" ]]; then
        oc scale deployment "$deploy" -n redhat-ods-applications --replicas=1 2>/dev/null || true
    fi
done

# -----------------------------------------------
# 6. Restore demo and workload namespaces
# -----------------------------------------------
info "Restoring workload namespaces..."
WORKLOAD_NAMESPACES="ossm-ai-models ossm-bookinfo ossm-restapi ossm-httpbin ossm-mesh-demo ossm-enrollment-test sonataflow-infra quarkus-grpc"
for ns in ${WORKLOAD_NAMESPACES}; do
    for deploy in $(oc get deployments -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        CURRENT=$(oc get deployment "$deploy" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null)
        if [[ "$CURRENT" == "0" ]]; then
            info "  Scaling up: $ns/$deploy"
            oc scale deployment "$deploy" -n "$ns" --replicas=1 2>/dev/null || true
        fi
    done
    for sts in $(oc get statefulsets -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        CURRENT=$(oc get statefulset "$sts" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null)
        if [[ "$CURRENT" == "0" ]]; then
            info "  Scaling up: $ns/$sts"
            oc scale statefulset "$sts" -n "$ns" --replicas=1 2>/dev/null || true
        fi
    done
done

# -----------------------------------------------
# 7. Sync ArgoCD Applications
# -----------------------------------------------
info "Syncing ArgoCD Applications..."
echo ""

APPS=$(oc get applications -n openshift-gitops -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
for app in ${APPS}; do
    info "  Syncing: $app"
    oc annotate application "$app" -n openshift-gitops \
        argocd.argoproj.io/refresh=normal --overwrite 2>/dev/null || true
done

echo ""
warn "ArgoCD Applications have been refreshed."
warn "Resources deleted during teardown (InferenceServices, etc.)"
warn "will be recreated on the next ArgoCD sync."
echo ""
info "To fully sync an app:  oc patch application <name> -n openshift-gitops --type merge -p '{\"operation\":{\"initiatedBy\":{\"username\":\"admin\"},\"sync\":{}}}'"
echo ""

# -----------------------------------------------
# 8. Post-restore checks
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
info "Keycloak runs externally on Wing (sso.ultra.lab) — no restore needed."
info "InferenceServices will need an ArgoCD sync or manual re-apply."

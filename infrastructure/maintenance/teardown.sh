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
if [[ "$SKIP_CONFIRM" != "true" ]]; then
    read -p "Continue? (yes/no): " CONFIRM
    if [[ "${CONFIRM}" != "yes" ]]; then
        echo "Aborted."
        exit 0
    fi
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
# 4. Scale down observability stack
# -----------------------------------------------
info "Scaling down observability stack..."

# Tempo in observability namespace
for deploy in $(oc get deployments -n observability -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    oc scale deployment "$deploy" -n observability --replicas=0 2>/dev/null || true
done
for sts in $(oc get statefulsets -n observability -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    oc scale statefulset "$sts" -n observability --replicas=0 2>/dev/null || true
done

# Tempo in tracing-system namespace
for deploy in $(oc get deployments -n tracing-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    oc scale deployment "$deploy" -n tracing-system --replicas=0 2>/dev/null || true
done
for sts in $(oc get statefulsets -n tracing-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    oc scale statefulset "$sts" -n tracing-system --replicas=0 2>/dev/null || true
done

# OpenTelemetry collector
oc scale deployment -n opentelemetrycollector --all --replicas=0 2>/dev/null || true

# COO service mesh monitoring
for sts in $(oc get statefulsets -n coo-service-mesh -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    oc scale statefulset "$sts" -n coo-service-mesh --replicas=0 2>/dev/null || true
done

# MinIO (S3 backend for Tempo/Loki)
oc scale deployment minio -n minio --replicas=0 2>/dev/null || true

# Cluster observability operator
oc scale deployment -n openshift-cluster-observability-operator --all --replicas=0 2>/dev/null || true

# -----------------------------------------------
# 5. Scale down service mesh components
# -----------------------------------------------
info "Scaling down service mesh..."
for deploy in $(oc get deployments -n istio-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    oc scale deployment "$deploy" -n istio-system --replicas=0 2>/dev/null || true
done
oc scale deployment -n istio-ingress --all --replicas=0 2>/dev/null || true

# -----------------------------------------------
# 6. Scale down operators in openshift-operators
# -----------------------------------------------
info "Scaling down operators..."
for deploy in $(oc get deployments -n openshift-operators -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    oc scale deployment "$deploy" -n openshift-operators --replicas=0 2>/dev/null || true
done

# -----------------------------------------------
# 7. Scale down demo and workload namespaces
# -----------------------------------------------
info "Scaling down demo and workload namespaces..."
WORKLOAD_NAMESPACES="ossm-ai-models ossm-bookinfo ossm-restapi ossm-httpbin ossm-mesh-demo ossm-enrollment-test sonataflow-infra quarkus-grpc"
for ns in ${WORKLOAD_NAMESPACES}; do
    for deploy in $(oc get deployments -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        oc scale deployment "$deploy" -n "$ns" --replicas=0 2>/dev/null || true
    done
    for sts in $(oc get statefulsets -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        oc scale statefulset "$sts" -n "$ns" --replicas=0 2>/dev/null || true
    done
done

# -----------------------------------------------
# 8. Scale down RHDH
# -----------------------------------------------
info "Scaling down Developer Hub..."
oc scale deployment backstage-developer-hub -n rhdh --replicas=0 2>/dev/null || true
oc scale statefulset backstage-psql-developer-hub -n rhdh --replicas=0 2>/dev/null || true
oc scale deployment -n rhdh-operator --all --replicas=0 2>/dev/null || true

# -----------------------------------------------
# 9. Scale down External Secrets operator
# -----------------------------------------------
info "Scaling down External Secrets operator..."
oc scale deployment -n external-secrets-operator --all --replicas=0 2>/dev/null || true

# -----------------------------------------------
# 10. Clean up any remaining PDBs that block drains
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
info "Keycloak runs externally on Wing (sso.ultra.lab) — not affected."
info ""
info "You can now safely:"
info "  - Apply MachineConfig changes (node reboots)"
info "  - Perform cluster upgrades"
info "  - Run maintenance tasks"
info ""
info "To restore: ./restore.sh"

#!/bin/bash
#
# Logging Stack Teardown
#
# Removes the OpenShift Logging + Loki Operator stack entirely.
# This clears the upgrade blocker from version-pinned operators
# and frees up cluster resources.
#
# Restore with: ./logging-restore.sh
#

set -euo pipefail

SKIP_CONFIRM=false
[[ "${1:-}" == "-y" ]] && SKIP_CONFIRM=true

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

if ! oc whoami &>/dev/null; then
    error "Not logged into an OpenShift cluster. Aborting."
    exit 1
fi

echo ""
echo "============================================"
echo "  Logging Stack Teardown"
echo "============================================"
echo "  Cluster: $(oc whoami --show-server)"
echo "  User:    $(oc whoami)"
echo "  Date:    $(date)"
echo "============================================"
echo ""
warn "This will completely remove:"
warn "  - ClusterLogForwarder (collector)"
warn "  - LokiStack (logging-loki)"
warn "  - Cluster Logging operator"
warn "  - Loki Operator"
warn "  - openshift-logging namespace"
warn ""
warn "Stored logs will be lost (data remains in MinIO bucket)."
echo ""
if [[ "$SKIP_CONFIRM" != "true" ]]; then
    read -p "Continue? (yes/no): " CONFIRM
    if [[ "${CONFIRM}" != "yes" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo ""

info "Deleting ClusterLogForwarder..."
oc delete clusterlogforwarder collector -n openshift-logging --ignore-not-found 2>/dev/null || true

info "Waiting for collectors to stop..."
oc wait --for=delete daemonset/collector -n openshift-logging --timeout=60s 2>/dev/null || true

info "Deleting LokiStack..."
oc delete lokistack logging-loki -n openshift-logging --ignore-not-found 2>/dev/null || true

info "Waiting for LokiStack pods to terminate..."
sleep 10

info "Deleting Cluster Logging subscription and CSV..."
CSV_LOGGING=$(oc get csv -n openshift-logging -o jsonpath='{.items[?(@.spec.displayName=="Red Hat OpenShift Logging")].metadata.name}' 2>/dev/null || true)
oc delete subscription cluster-logging -n openshift-logging --ignore-not-found 2>/dev/null || true
if [[ -n "$CSV_LOGGING" ]]; then
    oc delete csv "$CSV_LOGGING" -n openshift-logging --ignore-not-found 2>/dev/null || true
fi

info "Deleting Loki Operator subscription and CSV..."
CSV_LOKI=$(oc get csv -n openshift-operators-redhat -o jsonpath='{.items[?(@.spec.displayName=="Loki Operator")].metadata.name}' 2>/dev/null || true)
oc delete subscription loki-operator -n openshift-operators-redhat --ignore-not-found 2>/dev/null || true
if [[ -n "$CSV_LOKI" ]]; then
    # Loki CSV may exist in multiple namespaces
    oc delete csv "$CSV_LOKI" -n openshift-operators-redhat --ignore-not-found 2>/dev/null || true
    oc delete csv "$CSV_LOKI" -n openshift-logging --ignore-not-found 2>/dev/null || true
fi

info "Deleting OperatorGroups..."
oc delete operatorgroup -n openshift-logging --all --ignore-not-found 2>/dev/null || true
oc delete operatorgroup -n openshift-operators-redhat --all --ignore-not-found 2>/dev/null || true

info "Cleaning up remaining resources in openshift-logging..."
oc delete all --all -n openshift-logging --ignore-not-found 2>/dev/null || true

echo ""
info "============================================"
info "  Logging stack removed"
info "============================================"
info ""
info "The upgrade blocker from loki-operator/cluster-logging"
info "should clear within a few minutes."
info ""
info "MinIO bucket 'logging-loki' still contains historical data."
info "To restore: ./logging-restore.sh"

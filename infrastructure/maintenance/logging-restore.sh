#!/bin/bash
#
# Logging Stack Restore
#
# Reinstalls the OpenShift Logging + Loki Operator stack.
# Uses MinIO for S3 storage (same as Tempo).
#
# Counterpart to: ./logging-teardown.sh
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
echo "  Logging Stack Restore"
echo "============================================"
echo "  Cluster: $(oc whoami --show-server)"
echo "  User:    $(oc whoami)"
echo "  Date:    $(date)"
echo "============================================"
echo ""
if [[ "$SKIP_CONFIRM" != "true" ]]; then
    read -p "Install logging stack? (yes/no): " CONFIRM
    if [[ "${CONFIRM}" != "yes" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo ""

# -----------------------------------------------
# 1. Create namespaces and OperatorGroups
# -----------------------------------------------
info "Creating namespaces..."
oc apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-logging
  labels:
    name: openshift-logging
    openshift.io/cluster-monitoring: "true"
---
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-operators-redhat
  labels:
    name: openshift-operators-redhat
    openshift.io/cluster-monitoring: "true"
EOF

info "Creating OperatorGroups..."
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-logging-og
  namespace: openshift-logging
spec:
  targetNamespaces:
    - openshift-logging
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-operators-redhat-og
  namespace: openshift-operators-redhat
spec: {}
EOF

# -----------------------------------------------
# 2. Install operators
# -----------------------------------------------
info "Installing Loki Operator..."
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: loki-operator
  namespace: openshift-operators-redhat
spec:
  channel: stable-6.6
  installPlanApproval: Automatic
  name: loki-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

info "Installing Cluster Logging operator..."
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-logging
  namespace: openshift-logging
spec:
  channel: stable-6.6
  installPlanApproval: Automatic
  name: cluster-logging
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

info "Waiting for operators to install (this may take a couple minutes)..."
for i in $(seq 1 30); do
    LOKI_PHASE=$(oc get csv -n openshift-operators-redhat -o jsonpath='{.items[?(@.spec.displayName=="Loki Operator")].status.phase}' 2>/dev/null || true)
    LOGGING_PHASE=$(oc get csv -n openshift-logging -o jsonpath='{.items[?(@.spec.displayName=="Red Hat OpenShift Logging")].status.phase}' 2>/dev/null || true)
    if [[ "$LOKI_PHASE" == "Succeeded" && "$LOGGING_PHASE" == "Succeeded" ]]; then
        info "Both operators installed successfully."
        break
    fi
    echo -n "."
    sleep 10
done
echo ""

# -----------------------------------------------
# 3. Create MinIO credentials secret
# -----------------------------------------------
info "Creating MinIO credentials secret for LokiStack..."
oc apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: loki-minio-credentials
  namespace: openshift-logging
type: Opaque
stringData:
  access_key_id: minioadmin
  access_key_secret: minioadmin
  bucketnames: logging-loki
  endpoint: http://minio.minio.svc.cluster.local:9000
EOF

# -----------------------------------------------
# 4. Create LokiStack
# -----------------------------------------------
info "Creating LokiStack..."
oc apply -f - <<'EOF'
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  size: 1x.demo
  storage:
    schemas:
      - effectiveDate: "2024-01-01"
        version: v13
    secret:
      name: loki-minio-credentials
      type: s3
  limits:
    global:
      ingestion:
        ingestionBurstSize: 6
        ingestionRate: 4
      queries:
        maxEntriesLimitPerQuery: 5000
        queryTimeout: 3m
      retention:
        days: 1
  tenants:
    mode: openshift-logging
EOF

info "Waiting for LokiStack to become ready..."
for i in $(seq 1 30); do
    READY=$(oc get lokistack logging-loki -n openshift-logging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [[ "$READY" == "True" ]]; then
        info "LokiStack is ready."
        break
    fi
    echo -n "."
    sleep 10
done
echo ""

# -----------------------------------------------
# 5. Create ClusterLogForwarder
# -----------------------------------------------
info "Creating ClusterLogForwarder..."
oc apply -f - <<'EOF'
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: collector
  namespace: openshift-logging
spec:
  managementState: Managed
  outputs:
    - name: default-lokistack
      type: lokiStack
      lokiStack:
        target:
          name: logging-loki
          namespace: openshift-logging
        authentication:
          token:
            from: serviceAccount
      tls:
        ca:
          configMapName: openshift-service-ca.crt
          key: service-ca.crt
  pipelines:
    - name: default-logstore
      inputRefs:
        - application
        - infrastructure
      outputRefs:
        - default-lokistack
EOF

echo ""
info "============================================"
info "  Logging stack restored"
info "============================================"
info ""
info "Collectors will start rolling out on each node."
info "Logs will appear in Observe -> Logs once LokiStack is ingesting."
info ""
info "Note: The operator versions may trigger an upgrade blocker."
info "To clear it, update the subscription channels to the latest."

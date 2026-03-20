#!/bin/bash
#
# Model Serving Toggle — Start/Stop KServe InferenceServices
#
# Uses a modelcar (OCI image) stored in the internal registry,
# so the model is cached locally on nodes and doesn't need to
# be re-downloaded from HuggingFace on each start.
#
# Usage:
#   ./model-serve.sh start    # Deploy the InferenceService
#   ./model-serve.sh stop     # Remove the InferenceService
#   ./model-serve.sh status   # Check current state
#

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

NAMESPACE="super-slim-demo"
ISVC_NAME="phi-4-mini"
MODELCAR_IMAGE="image-registry.openshift-image-registry.svc:5000/${NAMESPACE}/phi-4-mini-modelcar:latest"

usage() {
    echo "Usage: $0 {start|stop|status}"
    echo ""
    echo "  start   - Deploy phi-4-mini InferenceService (modelcar, no download)"
    echo "  stop    - Remove phi-4-mini InferenceService (frees 12Gi+ memory)"
    echo "  status  - Show current InferenceService state"
    exit 1
}

do_start() {
    if oc get inferenceservice "$ISVC_NAME" -n "$NAMESPACE" &>/dev/null; then
        warn "InferenceService $ISVC_NAME already exists"
        do_status
        return
    fi

    info "Deploying InferenceService $ISVC_NAME with modelcar..."

    cat <<EOF | oc apply -f -
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: ${ISVC_NAME}
  namespace: ${NAMESPACE}
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
spec:
  predictor:
    model:
      runtime: vllm-cpu-runtime
      modelFormat:
        name: vLLM
      storageUri: oci://${MODELCAR_IMAGE}
      resources:
        requests:
          cpu: "4"
          memory: 12Gi
        limits:
          cpu: "8"
          memory: 16Gi
EOF

    info "InferenceService created. Model is loading from local cache (no download)."
    info "Monitor startup with: oc get inferenceservice $ISVC_NAME -n $NAMESPACE -w"
}

do_stop() {
    if ! oc get inferenceservice "$ISVC_NAME" -n "$NAMESPACE" &>/dev/null; then
        warn "InferenceService $ISVC_NAME does not exist — nothing to stop"
        return
    fi

    info "Removing InferenceService $ISVC_NAME..."
    oc delete inferenceservice "$ISVC_NAME" -n "$NAMESPACE"
    info "InferenceService removed. Memory freed."
}

do_status() {
    echo ""
    if oc get inferenceservice "$ISVC_NAME" -n "$NAMESPACE" &>/dev/null; then
        info "InferenceService:"
        oc get inferenceservice "$ISVC_NAME" -n "$NAMESPACE" -o wide
        echo ""
        info "Pod:"
        oc get pods -n "$NAMESPACE" -l "serving.kserve.io/inferenceservice=$ISVC_NAME" --no-headers 2>/dev/null || echo "  No pods found"
    else
        warn "InferenceService $ISVC_NAME is not deployed"
    fi
    echo ""
}

# --- Main ---
if [[ $# -lt 1 ]]; then
    usage
fi

case "$1" in
    start)  do_start ;;
    stop)   do_stop ;;
    status) do_status ;;
    *)      usage ;;
esac

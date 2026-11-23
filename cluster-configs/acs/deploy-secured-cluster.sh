#!/bin/bash
#
# Create the ACS cluster registration secret (CRS) for the local SecuredCluster.
#
# The SecuredCluster CR itself is deployed by the `acs` Argo CD Application; it
# only needs this secret to register with Central. The CRS contains secrets, so
# it is applied straight to the cluster and never written to Git or disk.
#
# Uses Central's REST API (no roxctl needed). The CRS is only needed for initial
# registration; afterwards Sensor uses its own issued certificates.
#
set -euo pipefail

NAMESPACE="stackrox"
CRS_NAME="${1:-tallgeese-crs}"

echo "Waiting for Central to be available..."
oc wait --for=condition=Available central/stackrox-central-services -n "${NAMESPACE}" --timeout=600s

HOST=$(oc get route central -n "${NAMESPACE}" -o jsonpath='{.spec.host}')
PASS=$(oc get secret central-htpasswd -n "${NAMESPACE}" -o go-template='{{index .data "password" | base64decode}}')

echo "Generating CRS '${CRS_NAME}' via https://${HOST} ..."
curl -sfk -u "admin:${PASS}" -X POST "https://${HOST}/v1/cluster-init/crs" \
  -H 'Content-Type: application/json' -d "{\"name\":\"${CRS_NAME}\"}" \
  | python3 -c 'import json,sys,base64; sys.stdout.write(base64.b64decode(json.load(sys.stdin)["crs"]).decode())' \
  | oc apply -n "${NAMESPACE}" -f -
unset PASS

echo "Done. Sync the acs Argo CD Application if the SecuredCluster is not yet deployed."

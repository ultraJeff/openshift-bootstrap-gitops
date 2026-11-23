# Red Hat Advanced Cluster Security (ACS/RHACS)

Demo-sized RHACS 5.0 for the 3-node tallgeese lab, deployed by the `acs` Argo CD
Application (`applications/acs.yaml`, manual sync, ServerSideApply, no
resources-finalizer).

## Components

| File | What |
|---|---|
| `acs-operator.yaml` | `rhacs-operator` namespace, OperatorGroup, Subscription (channel `rhacs-5.0`, pinned) |
| `stackrox-namespace.yaml` | `stackrox` namespace for Central and the SecuredCluster |
| `acs-central.yaml` | Central + Central DB + Scanner V4, demo-sized |
| `acs-secured-cluster.yaml` | SecuredCluster `local-cluster` (clusterName `tallgeese`) |
| `deploy-secured-cluster.sh` | Generates the cluster registration secret (CRS) via Central's API |

## Sizing (CPU requests; requests are the constraint on this cluster)

| Component | Here | Documented default |
|---|---|---|
| Central | 500m / 2Gi | 1.5 / 4Gi |
| Central DB | 500m / 2Gi, 100Gi PVC `central-db` | 4 / 8Gi |
| Scanner V4 indexer | 1 × 300m / 1.5Gi | 3 replicas, 4.5 total |
| Scanner V4 matcher | 1 × 300m / 3Gi | 2 replicas, 1 total |
| Scanner V4 DB | 300m / 2Gi, 50Gi PVC | 1 / 4Gi |
| Sensor | 200m / 500Mi | 2 / 4Gi |
| Admission controller | 1 × 50m / 100Mi | |
| Collector (per node, CORE_BPF) | 50m / 320Mi | |

## ACS 5.0 gotchas

- `spec.central.persistence` is an **unused legacy field** (since 4.6). Configure
  Central DB storage/resources under `spec.central.db`.
- With `scannerV4.scannerComponent: Disabled`, the 5.0 operator deployed **no
  scanner at all** (no StackRox Scanner pods either), so Scanner V4 is enabled.
- SecuredCluster: `admissionControl.dynamic` was removed; `listenOn*`,
  `timeoutSeconds` and `contactImageScanners` are deprecated. Use
  `enforcement` / `bypass` / `failurePolicy`.
- Collector `EBPF` is legacy; use `CORE_BPF`.

## Install / rebuild

1. Register the app: `oc apply -f applications/acs.yaml`. Sync it (installs the
   operator, Central, Scanner V4).
2. Once Central is Available, create the CRS (secret, not in Git):
   `./cluster-configs/acs/deploy-secured-cluster.sh`
3. Sync the app again if the SecuredCluster hasn't reconciled yet.

A CRS created through the API without an explicit validity expires after ~24h.
It is only used for the first registration; after that Sensor uses its own
certificates. Generate a new one when adding or re-registering a cluster.

## Access

```bash
oc -n stackrox get route central -o jsonpath='https://{.spec.host}{"\n"}'
oc -n stackrox get secret central-htpasswd -o go-template='{{index .data "password" | base64decode}}'
```

Log in as `admin`.

## Troubleshooting

```bash
oc get central,securedcluster -n stackrox
oc get pods -n stackrox -o wide
oc logs -n rhacs-operator deploy/rhacs-operator-controller-manager --since=10m
```

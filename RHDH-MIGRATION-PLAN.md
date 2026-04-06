# RHDH Feature Parity Migration Plan

**Source**: `rhdh-bootstrap` (k4mmh cluster)
**Target**: `openshift-bootstrap-gitops` (tallgeese homelab)
**Cluster**: `api.tallgeese.ultra.lab:6443`
**RHDH Version**: 1.9.0 (operator auto-upgraded from 1.8, subscription on `fast-1.8` channel)

## Context

Both repos manage RHDH deployments via ArgoCD. The `rhdh-bootstrap` repo has additional plugins and configuration that the homelab repo lacks. The RHDH operator auto-upgraded to 1.9 on tallgeese.

**Not installed on tallgeese** (do not plan for these): Orchestrator / SonataFlow, Tekton Pipelines, Dev Spaces, Quay registry.

## RHDH 1.9 Operator Behaviors (Lessons Learned)

- The operator controls the RHDH image digest; pinning in the Backstage CR is overridden.
- The operator creates a **separate** ConfigMap (`backstage-dynamic-plugins-developer-hub`) from the user-provided one (`rhdh-dynamic-plugins`). Changes to the user ConfigMap require operator reconciliation.
- The catalog index `dynamic-plugins.default.yaml` may reference unbundled plugins as enabled (e.g. `backstage-community-plugin-redhat-argocd`). These must be explicitly overridden with `disabled: true`.
- OCI plugins can use `{{inherit}}` for version resolution when the defaults are included, or pinned versions (e.g. `bs_1.45.3__1.0.2`) for stability.
- The `dynamic-plugins-root` PVC caches downloaded plugins across restarts and can harbor stale lock files.

## Migration Checklist

### 1. Dynamic Plugins (`dynamic-plugins.yaml`)

Add the following plugins (all using OCI or bundled paths):

- [x] **Topology** — `./dynamic-plugins/dist/backstage-community-plugin-topology` (bundled)
- [x] **Scaffolder utils** — `oci://ghcr.io/redhat-developer/rhdh-plugin-export-overlays/roadiehq-scaffolder-backend-module-utils:{{inherit}}` (OCI)

### 2. App Config (`app-config-production.yaml`)

- [x] Add custom software templates catalog location
- [x] Add `github.com` to `backend.reading.allow`
- [x] Normalize `githubOrg.id` from `ultraJeffOrg` to `githubOrg` (cosmetic)

### 3. RBAC Policies (`rbac-policies.yaml`)

Add missing permissions:

- [x] `extensions.plugin.configuration.read` — read, allow (for Extensions UI)
- [x] `extensions.plugin.configuration.write` — create, allow (for Extensions UI)
- [x] `extensions.plugin.configuration.delete` — delete, allow (for Extensions UI)

### 4. Backstage CR (`rhdh-instance.yaml`)

- [x] Add `automountServiceAccountToken: true` to deployment patch (required for in-cluster Kubernetes plugin auth)

### 5. New Files

- [x] **`kubernetes-rbac.yaml`** — ClusterRole `rhdh-kubernetes-reader` + ClusterRoleBinding to `default` ServiceAccount in `rhdh` namespace
- [x] **`console-link.yaml`** — ConsoleLink to add RHDH to the OpenShift console Application Menu
- [x] Update **`kustomization.yaml`** to include both new resources

### 6. Extensions File Seeding

- [x] Init container `seed-extensions-file` added to Backstage CR deployment patch — creates `installed-dynamic-plugins.yaml` on the PVC if it doesn't already exist

## Removed Items

The following were in the original plan but removed because the required infrastructure is not installed on tallgeese:

- **Orchestrator** — SonataFlow / Serverless Logic operators, orchestrator plugins, RBAC policies, and `auth.externalAccess` for orchestrator. All removed from repo.
- **Tekton CI plugin** — No Tekton Pipelines on this cluster.
- **Quay plugin** — No Quay registry; `quay.uiUrl` config not needed.
- **TechDocs** (backend + frontend) — No doc builder/storage backend configured.
- **Tech Radar** — No data source configured.
- **Security Insights** — Requires GitHub Advanced Security.
- **Dev Spaces** — Not installed; `devSpaces.defaultNamespace` config not needed.
- **OCM** — No `catalog.providers.ocm` config.
- **Adoption Insights** — Plugin not in use.

# RHDH Feature Parity Migration Plan

**Source**: `rhdh-bootstrap` (k4mmh cluster)
**Target**: `openshift-bootstrap-gitops` (tallgeese homelab)
**Status**: In progress — Orchestrator done, several items remain

## Context

Both repos manage RHDH deployments via ArgoCD. The `rhdh-bootstrap` repo has additional plugins, configuration, and RBAC policies that the homelab repo lacks. Both repos have been upgraded to RHDH 1.9 (operator auto-upgrade), but the homelab is missing several features.

The RHDH operator on 1.9 always injects `includes: - dynamic-plugins.default.yaml` into the operator-managed ConfigMap regardless of what the user ConfigMap specifies. The operator also downloads and merges the catalog index from `registry.redhat.io`. The `dynamic-plugins-registry-auth` secret (created manually from the cluster's global pull-secret) is required for the init container's `skopeo` to authenticate.

## RHDH 1.9 Operator Behaviors (Lessons Learned)

- The operator controls the RHDH image digest; pinning in the Backstage CR is overridden.
- The operator creates a **separate** ConfigMap (`backstage-dynamic-plugins-developer-hub`) from the user-provided one (`rhdh-dynamic-plugins`). Changes to the user ConfigMap require operator reconciliation.
- The catalog index `dynamic-plugins.default.yaml` may reference unbundled plugins as enabled (e.g. `backstage-community-plugin-redhat-argocd`). These must be explicitly overridden with `disabled: true`.
- OCI plugins can use `{{inherit}}` for version resolution when the defaults are included, or pinned versions (e.g. `bs_1.45.3__1.0.2`) for stability.
- The `dynamic-plugins-root` PVC caches downloaded plugins across restarts and can harbor stale lock files.

## Migration Checklist

### 1. Dynamic Plugins (`dynamic-plugins.yaml`)

Add the following plugins (all using OCI or bundled paths):

- [ ] **Topology** — `./dynamic-plugins/dist/backstage-community-plugin-topology` (bundled)
- [ ] **Quay** — `oci://ghcr.io/redhat-developer/rhdh-plugin-export-overlays/backstage-community-plugin-quay:{{inherit}}` (OCI)
- [ ] **Scaffolder utils** — `oci://ghcr.io/redhat-developer/rhdh-plugin-export-overlays/roadiehq-scaffolder-backend-module-utils:{{inherit}}` (OCI)
- [ ] **TechDocs backend** — `./dynamic-plugins/dist/backstage-plugin-techdocs-backend-dynamic` (bundled)
- [ ] **TechDocs frontend** — `./dynamic-plugins/dist/backstage-plugin-techdocs` (bundled)
- [ ] **Tekton CI** — `oci://ghcr.io/redhat-developer/rhdh-plugin-export-overlays/backstage-community-plugin-tekton:{{inherit}}` (OCI, includes pluginConfig for mount points)
- [ ] **Tech Radar** — `./dynamic-plugins/dist/backstage-community-plugin-tech-radar` (bundled)
- [ ] **Security Insights** — `oci://ghcr.io/redhat-developer/rhdh-plugin-export-overlays/roadiehq-backstage-plugin-security-insights:{{inherit}}` (OCI)
- [ ] **OCM** — `disabled: true` (requires `catalog.providers.ocm` config not present)

Decision: Use `{{inherit}}` or pinned versions for OCI plugins?
- `{{inherit}}` auto-resolves from the catalog index (follows operator upgrades)
- Pinned versions (e.g. `bs_1.45.3__1.0.2`) are more stable but require manual updates

### 2. App Config (`app-config-production.yaml`)

- [ ] Add custom software templates catalog location:
  ```yaml
  - type: url
    target: https://raw.githubusercontent.com/ultraJeff/rhdh-software-templates/main/all.yaml
    rules:
      - allow: [Template]
  ```
- [ ] Add `github.com` to `backend.reading.allow`:
  ```yaml
  - host: github.com
  ```
- [ ] Add `quay` config (required by Quay OCI plugin):
  ```yaml
  quay:
    uiUrl: https://quay.io
  ```
- [ ] Add `devSpaces` config:
  ```yaml
  devSpaces:
    defaultNamespace: <username>-devspaces
  ```
- [ ] Normalize `githubOrg.id` from `ultraJeffOrg` to `githubOrg` (cosmetic)

### 3. RBAC Policies (`rbac-policies.yaml`)

Add missing permissions:

- [ ] `kubernetes.clusters.read` — read, allow (for Kubernetes plugin)
- [ ] `kubernetes.resources.read` — read, allow (for Kubernetes plugin)
- [ ] `catalog-entity` — read, allow (general catalog access)
- [ ] `adoption-insights.events.read` — read, allow (Adoption Insights plugin)
- [ ] `admin_plugins` role with:
  - `orchestrator.workflow` read
  - `orchestrator.workflow.use` update
  - `orchestrator.workflowAdminView` read
  - `orchestrator.instanceAdminView` read
  - `extensions.plugin.configuration.read` read
  - `extensions.plugin.configuration.write` create
  - `extensions.plugin.configuration.delete` delete
- [ ] Bind `admin_plugins` role to `user:default/admin`

### 4. Backstage CR (`rhdh-instance.yaml`)

- [ ] Add `automountServiceAccountToken: true` to deployment patch (required for in-cluster Kubernetes plugin auth)

### 5. New Files

- [ ] **`kubernetes-rbac.yaml`** — ClusterRole `rhdh-kubernetes-reader` granting read access to pods, deployments, services, routes, builds, etc. + ClusterRoleBinding to `default` ServiceAccount in `rhdh` namespace
- [ ] **`console-link.yaml`** — ConsoleLink to add RHDH to the OpenShift console Application Menu (needs tallgeese-specific URL)
- [ ] Update **`kustomization.yaml`** to include both new resources

### 6. Orchestrator (DONE)

- [x] Install the OpenShift Serverless Logic / SonataFlow operator → `cluster-configs/orchestrator/`
- [x] Add Orchestrator plugins (1.8.2) to `dynamic-plugins.yaml`
- [x] Pin RHDH operator to `fast-1.8` channel for compatibility
- [x] `sonataflow-platform-data-index-service` auto-created by RHDH operator via `dependencies: - ref: sonataflow`
- [x] ArgoCD Application created at `applications/orchestrator.yaml`

### 7. Extensions File Seeding

The `installed-dynamic-plugins.yaml` file must exist on the `dynamic-plugins-root` PVC for the extensions installation feature to work. The `rhdh-bootstrap` repo has an `init.sh` Phase 5 that handles this automatically. For the homelab:

- [ ] Manually create the file via `oc exec` if not present, or
- [ ] Add a Job/init script to the GitOps repo that seeds it

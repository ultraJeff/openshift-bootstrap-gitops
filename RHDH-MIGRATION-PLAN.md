# RHDH Developer Experience Plan

**Cluster**: `api.tallgeese.ultra.lab:6443` (tallgeese homelab)
**RHDH Version**: 1.9.0 (operator subscription on `fast-1.8` channel)
**Goal**: Enable a full inner-loop developer experience — Quarkus app creation via a software template, Tekton CI pipelines, and Dev Spaces for cloud-based development, all surfaced in the Developer Hub catalog.

## Overview

```
Developer Hub (catalog) ──> Software Template (scaffolder)
        │                          │
        │                          ├── Scaffolds Quarkus app repo on GitHub
        │                          ├── Creates Tekton PipelineRun (first build)
        │                          └── Registers catalog entity with Dev Spaces link
        │
        ├── Tekton CI tab ──────── Pipeline runs, task logs
        ├── Topology tab ────────── Workload visualization
        └── Dev Spaces link ─────── Opens workspace in browser
```

## Phase 1: Install Tekton Pipelines

### 1.1 Operator Installation

- [ ] Create `cluster-configs/tekton/` directory with:
  - `kustomization.yaml`
  - `tekton-operator.yaml` — Namespace (`openshift-pipelines`), Subscription for `openshift-pipelines-operator-rh` on `latest` channel
- [ ] Create `applications/tekton.yaml` — ArgoCD Application pointing at `cluster-configs/tekton/`
- [ ] Add to `applications/kustomization.yaml`

### 1.2 RHDH Tekton Plugin

- [ ] Add Tekton plugin to `dynamic-plugins.yaml`:
  ```yaml
  - package: 'oci://ghcr.io/redhat-developer/rhdh-plugin-export-overlays/backstage-community-plugin-tekton:{{inherit}}'
    disabled: false
    pluginConfig:
      dynamicPlugins:
        frontend:
          backstage-community-plugin-tekton:
            mountPoints:
              - mountPoint: entity.page.ci/cards
                importName: TektonCI
                config:
                  layout:
                    gridColumn: 1 / -1
  ```
- [ ] RBAC already has `tekton.view.read` in `role:default/plugins` — verify it works

### 1.3 Tekton Pipeline Definition

- [ ] Create a reusable Tekton Pipeline for Quarkus apps (build + deploy):
  - `git-clone` → `maven` (or `s2i-java`) → `buildah` → `kubernetes-actions` (deploy)
  - Store in the software template repo (`ultraJeff/rhdh-software-templates`) or in-cluster via GitOps
- [ ] Decide on image registry: internal OpenShift registry vs external

## Phase 2: Install Dev Spaces

### 2.1 Operator Installation

- [ ] Create `cluster-configs/devspaces/` directory with:
  - `kustomization.yaml`
  - `devspaces-operator.yaml` — Subscription for `devspaces` operator on `stable` channel
  - `devspaces-instance.yaml` — `CheCluster` CR with default configuration
- [ ] Create `applications/devspaces.yaml` — ArgoCD Application
- [ ] Add to `applications/kustomization.yaml`

### 2.2 RHDH Dev Spaces Integration

- [ ] Add `devSpaces` config to `app-config-production.yaml`:
  ```yaml
  devSpaces:
    defaultNamespace: <username>-devspaces
  ```
  (The namespace pattern may need adjustment based on CheCluster config)

## Phase 3: Quarkus Software Template

### 3.1 Template Skeleton

Create a new template in `ultraJeff/rhdh-software-templates` that:

- [ ] Prompts for: component name, group ID, artifact ID, description, owner
- [ ] Scaffolds a Quarkus project (Maven, REST starter, health extensions)
- [ ] Includes a `devfile.yaml` for Dev Spaces (Quarkus universal developer image)
- [ ] Includes a `catalog-info.yaml` with:
  - `backstage.io/techdocs-ref` (if TechDocs is added later)
  - `backstage.io/kubernetes-id` annotation for Topology/Kubernetes plugins
  - Dev Spaces link annotation (`devspaces.io/editor-url` or equivalent)
  - Tekton pipeline annotation for CI tab
- [ ] Includes a `Dockerfile` or uses s2i for container builds
- [ ] Includes OpenShift manifests (Deployment, Service, Route) or a Helm chart

### 3.2 Template Actions

- [ ] `publish:github` — create repo under the user's GitHub org
- [ ] `catalog:register` — register the new component in RHDH
- [ ] `kubernetes:apply` — create the Tekton PipelineRun for initial build (or trigger via webhook)

### 3.3 Tekton Trigger (Optional)

- [ ] Add a Tekton `TriggerTemplate` + `EventListener` for GitHub webhook-driven builds
- [ ] Configure GitHub webhook in the template's `publish:github` step

## Phase 4: Validation

- [ ] Create a test app using the template from the RHDH UI
- [ ] Verify the Tekton pipeline runs and completes (CI tab in catalog entity)
- [ ] Verify the Topology tab shows the deployed workload
- [ ] Verify the Dev Spaces link opens a workspace with the Quarkus project
- [ ] Verify the Kubernetes tab shows pods/logs

## Dependencies & Decisions

| Decision | Options | Notes |
|----------|---------|-------|
| Image registry | Internal OpenShift registry / External (Quay.io, GHCR) | Internal is simplest; external needs pull secrets |
| Pipeline style | `buildah` + raw manifests / s2i / Helm + ArgoCD | Helm + ArgoCD gives GitOps-native deployment |
| Dev Spaces devfile | Universal Developer Image / custom | UDI is simplest, custom allows pre-baked tools |
| Tekton triggers | Webhook-driven / manual PipelineRun only | Webhooks need a publicly routable EventListener |

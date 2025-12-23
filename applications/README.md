# ArgoCD Applications

This folder contains ArgoCD Application manifests that define what gets deployed to the cluster.

## Applications

| Application | Path | Description |
|-------------|------|-------------|
| `developer-hub` | `cluster-configs/developer-hub` | Red Hat Developer Hub |

## Usage

### Deploy All Applications

```bash
oc apply -k applications/
```

### Deploy Individual Application

```bash
oc apply -f applications/developer-hub.yaml
```

## Prerequisites

Some applications require secrets to be applied manually before the Application can sync:

### Developer Hub

```bash
# Copy and fill in secret templates
cd cluster-configs/developer-hub
cp keycloak-secrets.yaml.example keycloak-secrets.yaml
cp rhdh-secrets.yaml.example rhdh-secrets.yaml
cp argocd-secrets.yaml.example argocd-secrets.yaml

# Edit the files with your values, then apply
oc apply -k cluster-configs/developer-hub/secrets/
```

## Adding New Applications

1. Create a new `<app-name>.yaml` in this folder
2. Add it to `kustomization.yaml`
3. Commit and push

The Application will be created but won't sync until you apply it to the cluster.

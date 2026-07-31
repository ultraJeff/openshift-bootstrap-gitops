# Keycloak (Deprecated — In-Cluster)

This directory contains the original in-cluster Keycloak deployment that ran on tallgeese. Keycloak now runs externally on Wing (`sso.ultra.lab`) as a Podman quadlet, managed by the [openshift-helper-node](https://github.com/ultraJeff/openshift-helper-node) repo.

The ArgoCD Application for this directory has been removed. These files are kept for reference but are not actively deployed.

## Current Keycloak setup

- **Host**: Wing (`sso.ultra.lab` / `192.168.8.100:8180`)
- **Realms**: `rhdh` (Developer Hub), `openshift` (cluster OIDC auth)
- **Managed by**: `openshift-helper-node` repo (`playbooks/deploy-keycloak.yml`)

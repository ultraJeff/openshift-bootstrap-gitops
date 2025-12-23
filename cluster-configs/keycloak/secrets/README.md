# Keycloak Secrets

This folder contains secrets that must be applied **manually** before deploying Keycloak via ArgoCD.

## Files

| File | Description | Location |
|------|-------------|----------|
| `keycloak-db-secret.yaml` | PostgreSQL database credentials | `secrets/` (gitignored) |
| `keycloak-db-secret.yaml.example` | Template for DB secret | `secrets/` |
| `rhdh-realm-import.yaml` | RHDH realm with users and client | Parent folder (gitignored) |
| `rhdh-realm-import.yaml.example` | Template for realm import | Parent folder |

## Setup Instructions

### 1. Create the secrets files

```bash
cd cluster-configs/keycloak

# DB secret
cp secrets/keycloak-db-secret.yaml.example secrets/keycloak-db-secret.yaml
# Edit: set your PostgreSQL username and password

# Realm import
cp rhdh-realm-import.yaml.example rhdh-realm-import.yaml
# Edit: Replace <RHDH_CLIENT_SECRET> with the same value used in
#       cluster-configs/developer-hub/secrets/keycloak-secrets.yaml (KEYCLOAK_CLIENT_SECRET, base64 decoded)
```

### 2. Apply the DB secret first

```bash
oc create namespace keycloak || true
oc apply -k cluster-configs/keycloak/secrets/
```

### 3. Deploy Keycloak via ArgoCD

```bash
oc apply -f applications/keycloak.yaml
# Wait for operator to install and Keycloak to start
```

### 4. Apply the realm import (after operator is ready)

```bash
# Wait for Keycloak CRDs to be available
oc wait --for=condition=Established crd/keycloaks.k8s.keycloak.org --timeout=120s

# Apply realm
oc apply -f cluster-configs/keycloak/rhdh-realm-import.yaml
```

## Important Notes

- The client secret in `rhdh-realm-import.yaml` **must match** the `KEYCLOAK_CLIENT_SECRET` in
  the Developer Hub secrets for OIDC authentication to work.
- Never commit the actual secret files to git.
- The realm import CRD only exists after the Keycloak operator installs, so it must be applied after ArgoCD syncs the operator.

# Developer Hub Secrets

These secrets must be applied **manually** before the ArgoCD Application can sync successfully.

## Setup Instructions

1. **Copy the example files** to create your secret files:

   ```bash
   cd cluster-configs/developer-hub
   cp keycloak-secrets.yaml.example keycloak-secrets.yaml
   cp rhdh-secrets.yaml.example rhdh-secrets.yaml
   cp argocd-secrets.yaml.example argocd-secrets.yaml
   ```

2. **Edit each file** with your actual values (see comments in each file for guidance)

3. **Apply the secrets**:

   ```bash
   oc apply -k cluster-configs/developer-hub/secrets/
   ```

4. **Verify secrets exist**:

   ```bash
   oc get secrets -n rhdh
   ```

## Secret Files

| File | Purpose |
|------|---------|
| `keycloak-secrets.yaml` | Keycloak SSO integration |
| `rhdh-secrets.yaml` | Backend secrets, GitHub App integration |
| `argocd-secrets.yaml` | ArgoCD plugin integration |

## Important Notes

- These files are **gitignored** - never commit them
- The main ArgoCD Application will fail to sync if secrets don't exist
- Update secrets by re-applying: `oc apply -k cluster-configs/developer-hub/secrets/`

# Citadel Research Agent Deployment Steps

This guide provides the *how*: an end-to-end, repeatable process to deploy or update the network‑isolated AI Research Agent environment.

---
## 1. Prerequisites
- Azure CLI (>= 2.62.0) + logged in: `az login`
- Azure Developer CLI (azd) installed
- Required provider registrations (run once per subscription):
  - `az provider register --namespace Microsoft.App`
  - `az provider register --namespace Microsoft.Network`
  - `az provider register --namespace Microsoft.CognitiveServices`
  - `az provider register --namespace Microsoft.DocumentDB`
  - `az provider register --namespace Microsoft.Search`
- Sufficient regional quota for: Azure AI (Agent Service), Cosmos DB, Storage, AI Search, Container Apps, Container Registry.

Optional (later hardening): Defender for Cloud (container registry scanning), Private DNS hub strategy, APIM internal VNet instance.

---
## 2. One-Time Environment Initialization
```bash
azd env new <envName> --location eastus2
```
This creates `.azure/<envName>` and local `.env` style configuration azd manages.

---
## 3. Key Parameters Overview (azure.yaml)
| Parameter | Typical Value | Purpose |
|-----------|---------------|---------|
| `stableSuffix` | e.g. `6jjr` | Deterministic 4-char suffix for resource reuse |
| `createContainerApp` | true / false | Two-phase toggle (infra-only vs full stack) |
| `internalAcaDnsEnabled` | true | Enable internal DNS provisioning logic |
| `internalAcaDnsMode` | `auto` initially | Auto discovers defaultDomain and creates `internal.<defaultDomain>` |
| `additionalInternalAcaDnsVnetIds` | [] | Link extra VNets (e.g., APIM) |
| `enableMonitoringPrivateEndpoints` | false (temp) | Disable until feature readiness |

---
## 4. First (Optionally Infra-Only) Deploy
If image not yet built:
```bash
azd up --no-prompt --subscription <subId>
```
(Or set `createContainerApp=false` first, then redeploy after image push.)

What happens:
1. VNet + Subnets (agent / aca / private-endpoint)
2. Container Registry (ACR) (currently with public access if Enabled)
3. AI Services Account + Project + Model Deployment
4. Storage, Cosmos DB (and database), AI Search
5. Private Endpoints + Private DNS Zones
6. Application Insights + Log Analytics
7. (If `createContainerApp=true`) Container Apps Environment (internal) + Container App
8. (If `internalAcaDnsEnabled` & auto) Deployment script creates internal zone

---
## 5. Build & Push Application Image
If not already present:
```bash
# From repo root or src
az acr build -t citadel-api:latest -r <acrName> ./src
```
Retrieve digest (optional for pinning):
```bash
digest=$(az acr repository show-manifests -n <acrName> --repository citadel-api --query "[?tags && contains(join(',',tags),'latest')].digest" -o tsv | head -n1)
```
Store digest for immutable deploy (optional):
```bash
azd env set API_IMAGE_DIGEST ${digest#sha256:}
```

---
## 6. Enable/Deploy Container App (If Deferred)
If previously skipped (`createContainerApp=false`):
1. Edit `azure.yaml`: set `createContainerApp: true`.
2. Run:
```bash
azd up
```

---
## 7. Discover Internal DNS (Auto Mode)
```bash
rg=$(az resource list --name cae-<suffix> --resource-type Microsoft.App/managedEnvironments --query "[0].resourceGroup" -o tsv)
az containerapp env show -n cae-<suffix> -g $rg --query properties.defaultDomain -o tsv
# List created internal zone
az network private-dns zone list -g $rg --query "[?starts_with(name,'internal.')].name" -o tsv
```
Resulting private zone: `internal.<defaultDomain>`
App ingress FQDN:
```bash
az containerapp show -n aca-<suffix> -g $rg --query properties.configuration.ingress.fqdn -o tsv
```

---
## 8. (Optional) Switch to Explicit DNS Mode
1. Capture zone from step 7.
2. Update parameters:
   - `internalAcaDnsMode: explicit`
   - `internalAcaDnsZoneName: internal.<defaultDomain>`
3. Redeploy:
```bash
azd up
```
Benefits: deterministic zone output, no deployment script rerun.

---
## 9. Integrate with APIM (Planned)
- APIM should be deployed in a VNet (internal mode).
- Add its VNet resource ID to `additionalInternalAcaDnsVnetIds` so it can resolve Container App FQDN.
- Backend in APIM: use `https://<app-ingress-fqdn>`; expose `/search`, `/chat`, `/health` routes.

---
## 10. Hardening Checklist (Post-Functional)
| Item | Action |
|------|--------|
| ACR Public Access | Set module param to `publicNetworkAccess: Disabled`; confirm private endpoint + DNS resolution |
| Digest Pinning | Use `containerImageDigest` param via env var (`API_IMAGE_DIGEST`) |
| Retention Policy | Configure ACR retention rule (CLI or Portal) |
| Vulnerability Scanning | Enable Defender for Cloud (container registry) |
| Monitoring PEs | Re-enable `enableMonitoringPrivateEndpoints` when feature available |
| Explicit DNS | Switch per step 8 |
| CI/CD | Add pipeline: build → scan → sign (future) → deploy |

---
## 11. Redeployment Safety
- Re-running `azd up` is safe (incremental mode).
- Changing `stableSuffix` creates a *new* resource set—only do intentionally.
- Turning `createContainerApp` from true → false does *not* delete the app; manual deletion required if needed.

---
## 12. Key CLI Queries
| Purpose | Command |
|---------|---------|
| Get container app FQDN | `az containerapp show -n aca-<suffix> -g <rg> --query properties.configuration.ingress.fqdn -o tsv` |
| Get internal DNS zone(s) | `az network private-dns zone list -g <rg> -o table` |
| List ACR images | `az acr repository list -n <acrName>` |
| Show latest tag digest | `az acr repository show-manifests -n <acrName> --repository citadel-api -o table` |
| Show AI Project endpoint | Output from deployment: `AZURE_AI_PROJECT_ENDPOINT` |

---
## 13. Rollback / Cleanup (Caution)
Full teardown (irreversible data loss if not backed up):
```bash
az group delete -n <resourceGroup> --yes --no-wait
```
If preserving data services but refreshing app plane:
1. Record resource IDs for Storage, Cosmos DB, AI Search.
2. Pass them back via parameters (`azureStorageAccountResourceId`, etc.).
3. Delete only Container App environment + registry if required, then redeploy with reuse.

---
## 14. Troubleshooting Quick Map
| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Container image pull fails | Identity lacks `AcrPull` or wrong registry server | Check role assignment & login server param |
| DNS not resolving internally | Zone not created or VNet not linked | Verify `internalAcaDnsEnabled` and mode; list zone links |
| App 503 on first hit | Cold start / initialization delay | Retry; check Log Analytics |
| Run status stuck (search) | Agent run not completing | Inspect agent run via SDK / increase wait timeout |

---
## 15. Next Enhancements
- Pipeline: GitHub Actions using `azd deploy` with digest capture.
- Policy Enforcement: Azure Policy for ACR public access lock.
- Logging: Export Log Analytics to storage for longer retention.
- Signing: Supply chain trust (cosign + policy gate).

---
## Summary
Follow steps 1–6 for initial standing environment; steps 7–8 for DNS stabilization; steps 9–10 for production hardening. Iterative, idempotent redeploys allow incremental adoption of stricter controls without disruptive redesign.

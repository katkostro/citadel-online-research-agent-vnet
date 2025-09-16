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

### 9.1 Manual VNet Peering (Immediate Enablement)
If you want APIM to reach the internal Container App before codifying:

```powershell
# Variables
$PRIMARY_VNET_RG="<rg>"
$PRIMARY_VNET_NAME="vnet-<envName>"  # or existing name
$APIM_VNET_RG="<apimRg>"
$APIM_VNET_NAME="<apimVnetName>"

# Primary -> APIM
az network vnet peering create `
  -g $PRIMARY_VNET_RG `
  --vnet-name $PRIMARY_VNET_NAME `
  -n to-$APIM_VNET_NAME `
  --remote-vnet /subscriptions/<subId>/resourceGroups/$APIM_VNET_RG/providers/Microsoft.Network/virtualNetworks/$APIM_VNET_NAME `
  --allow-vnet-access

# APIM -> Primary (reverse)
az network vnet peering create `
  -g $APIM_VNET_RG `
  --vnet-name $APIM_VNET_NAME `
  -n to-$PRIMARY_VNET_NAME `
  --remote-vnet /subscriptions/<subId>/resourceGroups/$PRIMARY_VNET_RG/providers/Microsoft.Network/virtualNetworks/$PRIMARY_VNET_NAME `
  --allow-vnet-access
```

Link APIM VNet to internal ACA DNS private zone (if auto mode already created it) so FQDN resolves:
```powershell
$ZONE_RG="<rg>"   # usually same RG as environment
$ZONE_NAME=$(az network private-dns zone list -g $ZONE_RG --query "[?starts_with(name,'internal.')].name | [0]" -o tsv)
az network private-dns link vnet create -g $ZONE_RG -z $ZONE_NAME -n apim-link `
  -v /subscriptions/<subId>/resourceGroups/$APIM_VNET_RG/providers/Microsoft.Network/virtualNetworks/$APIM_VNET_NAME `
  -e false --registration-enabled false
```

Validation:
```powershell
nslookup <app-ingress-fqdn> 10.<your.apim.vnet.dns.ip?>  # or rely on default VNet DNS
```

### 9.2 Codify Peering & DNS Linking in IaC
1. Edit `azure.yaml`:
   ```yaml
   apimVnetResourceId: /subscriptions/<subId>/resourceGroups/<apimRg>/providers/Microsoft.Network/virtualNetworks/<apimVnetName>
   additionalInternalAcaDnsVnetIds:
     - /subscriptions/<subId>/resourceGroups/<apimRg>/providers/Microsoft.Network/virtualNetworks/<apimVnetName>
   createApimReversePeering: true   # optional if you have rights
   ```
2. Run redeploy:
   ```powershell
   azd up
   ```
3. Reverse peering is created via deployment script if enabled (`createApimReversePeering: true`).

Deterministic Benefits:
- New environments automatically include APIM connectivity.
- Drift detection—manual deletions show up as missing on next `azd up`.
- Centralized documentation in parameters instead of ad-hoc shell history.

### 9.3 When to Switch from Manual to IaC
Do it once APIM integration is proven manually (latency, policy flow). Then codify so future scale-out (dev/test/prod) is effortless.

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

---
## Appendix A: Manual Internal DNS & APIM Connectivity Command Log (Session 2025-09-16)
These PowerShell (Azure CLI) commands were executed to manually establish internal DNS resolution for the Container App from the APIM VNet after discovering the internal zone was not present.

### A.1 Variables Used
```powershell
$RG_PRIMARY = "rg-citadel6-in-vnet"
$ENV_NAME   = "cae-6jjr"
$ZONE_NAME  = "internal.icyforest-5b750602.eastus2.azurecontainerapps.io"
$APIM_VNET_ID = "/subscriptions/e2a78235-937e-4d4b-8fda-bac4206be6a5/resourceGroups/citadel-ai-hub-gateway/providers/Microsoft.Network/virtualNetworks/vnet-nig77ltrdg3yc"
```

### A.2 Discover Container Apps Environment Static IP & Domain
```powershell
az containerapp env show -n $ENV_NAME -g $RG_PRIMARY --query "{name:name,location:location,staticIp:properties.staticIp,internalLoadBalancerIp:properties.internalLoadBalancerIp,defaultDomain:properties.defaultDomain}" -o table
```
Result (abbrev): StaticIp 172.29.2.62; defaultDomain icyforest-5b750602.eastus2.azurecontainerapps.io

### A.3 Inspect Existing Private DNS Zones (Confirmed Missing Internal Zone)
```powershell
az network private-dns zone list -g $RG_PRIMARY -o table
az network private-dns zone show -g $RG_PRIMARY -n $ZONE_NAME   # returned ResourceNotFound
```

### A.4 Create Internal Private DNS Zone
```powershell
az network private-dns zone create -g $RG_PRIMARY -n $ZONE_NAME -o table
```

### A.5 Link VNets to Zone (Primary & APIM)
```powershell
az network private-dns link vnet create -g $RG_PRIMARY -n link-primary-internal -z $ZONE_NAME -v vnet-citadel6 -e false
az network private-dns link vnet create -g $RG_PRIMARY -n link-apim-internal -z $ZONE_NAME -v $APIM_VNET_ID -e false
```

### A.6 Create A Record for Container App FQDN
FQDN host label: `aca-6jjr` → full: `aca-6jjr.$ZONE_NAME`

Attempt with unsupported `--ttl` flag (CLI version rejected):
```powershell
az network private-dns record-set a add-record -g $RG_PRIMARY -z $ZONE_NAME -n aca-6jjr -a 172.29.2.62 --ttl 30  # failed (unrecognized arguments)
```
Successful command (default TTL 3600 applied):
```powershell
az network private-dns record-set a add-record -g $RG_PRIMARY -z $ZONE_NAME -n aca-6jjr -a 172.29.2.62
```

### A.7 Verify A Record
```powershell
az network private-dns record-set a list -g $RG_PRIMARY -z $ZONE_NAME -o json
```
Excerpt:
```json
[
  {
    "name": "aca-6jjr",
    "aRecords": [{ "ipv4Address": "172.29.2.62" }],
    "ttl": 3600
  }
]
```

### A.8 (Previously Executed Earlier) VNet Peerings (If Re-Documentation Needed)
Shown for completeness—already established before this session; required for cross‑VNet DNS & traffic.
```powershell
# Primary -> APIM
az network vnet peering create -g rg-citadel6-in-vnet --vnet-name vnet-citadel6 -n to-vnet-nig77ltrdg3yc `
  --remote-vnet $APIM_VNET_ID --allow-vnet-access

# APIM -> Primary (run in APIM RG)
az network vnet peering create -g citadel-ai-hub-gateway --vnet-name vnet-nig77ltrdg3yc -n to-vnet-citadel6 `
  --remote-vnet /subscriptions/e2a78235-937e-4d4b-8fda-bac4206be6a5/resourceGroups/rg-citadel6-in-vnet/providers/Microsoft.Network/virtualNetworks/vnet-citadel6 `
  --allow-vnet-access
```

### A.9 Post-Record Validation (Recommended)
Run from APIM VNet context (VM / test container):
```powershell
nslookup aca-6jjr.$ZONE_NAME
curl -v http://aca-6jjr.$ZONE_NAME/health
```

### A.10 Notes & Lessons
- Internal zone was not auto-created (auto mode expectation), requiring manual creation—codify with `internalAcaDnsMode: explicit` + `internalAcaDnsZoneName` to prevent drift.
- Adding `--ttl` during `add-record` not supported in current CLI; default TTL of 3600 applied—adjust via `record-set a update` if needed.
- Peering must be bidirectional (both states Connected/FullyInSync) before DNS queries succeed across VNets.

### A.11 Suggested Parameter Update
```yaml
internalAcaDnsMode: explicit
internalAcaDnsZoneName: internal.icyforest-5b750602.eastus2.azurecontainerapps.io
additionalInternalAcaDnsVnetIds:
  - /subscriptions/e2a78235-937e-4d4b-8fda-bac4206be6a5/resourceGroups/citadel-ai-hub-gateway/providers/Microsoft.Network/virtualNetworks/vnet-nig77ltrdg3yc
```

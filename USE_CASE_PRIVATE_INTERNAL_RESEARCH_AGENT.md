# Private, Internal-Only Research Agent on Azure (Citadel Pattern)

## 1. Executive Summary
A single FastAPI "Research Agent" runs inside an **internal-only Azure Container Apps Environment (ACE)**, fronted by API Management (APIM) over private networking. All stateful and model-adjacent services (Azure AI Project, Cosmos DB, Azure Storage, Azure AI Search, Bing integration) are isolated via **private endpoints**, with deterministic DNS and optional explicit internal zone management. The agent exposes one canonical production endpoint: `/research` (plus an internal alias `/researcher/research` retained for backward compatibility). Deployment is fully reproducible with Bicep + `azd` and supports a two‑phase (infrastructure-first) workflow, immutable image digest pinning, and progressive hardening (monitoring private endpoints, health probes, explicit DNS).

This document unifies: architecture rationale, greenfield deployment guide, networking & DNS strategy, packaging/build procedures, peering, monitoring, security controls, troubleshooting history, and future enhancements.

---
## 2. Objectives & Non‑Goals
**Objectives**
- End-to-end private network isolation (no public data plane for core services).
- Deterministic naming & repeatable IaC deployments (`stableSuffix`, explicit DNS mode).
- Minimal, well-defined API surface (single `/research`).
- Separation of infrastructure lifecycle from application revision lifecycle.
- Observability via Application Insights & Log Analytics behind private endpoints.
- Clear rollback & forward deployment process.

**Non-Goals**
- Implementing production-grade agent research logic (placeholder currently).
- Providing multi-tenant request isolation beyond per-project partitioning.
- Public internet exposure of the container app (intentionally internal).

---
## 3. Architecture Overview
```
+-------------------+           +---------------------------+
|  Developer / CI   |           |      Operations / SRE     |
+---------+---------+           +-------------+-------------+
          | (azd up / ACR build)              |
          v                                   v
   +-------------+        Private VNet     +------------------+
   |  Azure ACR  |<-----+  (Spokes/Hubs) +-> Log Analytics    |
   +------+------+      |                |  & App Insights    |
          | (pull MI)   |                +---------+----------+
          v              |                          ^ (private ingestion planned)
+---------+--------------+----+   DNS: internal.<ACE defaultDomain>
|  Azure Container Apps   |   |  (private zone linked to APIM VNet)
|  Environment (internal) |   |
+------------+------------+   |
             | Internal ingress (FQDN: aca-<suffix>.internal.<domain>)
             v
       +-----+------+         +---------------------------+
       | Container  |  <----> |  Private Endpoints (PE)   |
       |  App (/research)     |  - AI Project / Foundry   |
       +-----+------+         |  - Cosmos DB              |
             |                |  - Azure Storage          |
             |                |  - Azure AI Search        |
             |                |  - (Monitoring PEs)       |
             v                +-------------+-------------+
        +----+----+                           |
        |  APIM   | (Internal mode / VNet)    |
        +----+----+                           |
             |  Private Peering + DNS         |
             v                                  
     (Enterprise Consumers)
```

---
## 4. Resource Inventory (Simplified)
| Category | Resource | Access | Notes |
|----------|----------|--------|-------|
| Compute | Container App Env + App | Internal only | targetPort 8000, single revision mode |
| Container Registry | ACR | Private (PE) | Premium SKU, MI-based pull |
| AI | Azure AI Account + Project | Private endpoints | Model deployments & agent hosting |
| Data | Cosmos DB (SQL) | Private endpoint | Thread / state storage |
| Data | Azure Storage (Blob) | Private endpoint | File & artifact storage |
| Search | Azure AI Search | Private endpoint | Vector / retrieval |
| External Data | Bing Search | Key-based | For grounding (future real logic) |
| Monitoring | App Insights + Log Analytics | Private endpoints (planned/enabled via module) | Telemetry & traces |
| Networking | VNet + Subnets (agent/aca/pe) | N/A | Delegated ACA subnet |
| DNS | Private zones (Cognitive, Search, Storage, etc.) | Linked | Internal ACA zone auto/explicit |
| Security | Managed Identity (System/User) | N/A | RBAC for pulls & data access |

---
## 5. Deployment Modes
| Mode | Use Case | Parameters |
|------|----------|------------|
| Greenfield (Full) | First-time infra + app | `createContainerApp=true` (default) |
| Two-Phase | Build infra first, add app after image ready | Initial: `createContainerApp=false` then redeploy with `true` |
| DNS Auto → Explicit | Stabilize after initial discovery | Start `internalAcaDnsMode=auto`, then redeploy `explicit` |

---
## 6. Greenfield Deployment Walkthrough
### 6.1 Prerequisites
- Azure CLI, Azure Developer CLI (`azd`)
- Provider registrations (see `DEPLOYMENT_STEPS.md` §1)
- Sufficient quota in target region

### 6.2 Initialize Environment
```
azd env new citadel-dev --location eastus2
```

### 6.3 First Provision (Auto DNS Mode)
```
azd up
```
What happens (ordered): VNet/Subnets → ACR → AI Account & Project → Cosmos/Storage/Search → Private Endpoints + DNS → Monitoring stack → ACA Env (internal) → (optionally) Container App → Auto internal DNS zone creation (if mode=auto).

### 6.4 Build & Push Image (If Two-Phase)
```
az acr build -t citadel-api:latest -r <acrName> ./src
```
Capture digest for pinning:
```
az acr repository show-manifests -n <acrName> --repository citadel-api -o table
```
Set env (optional):
```
azd env set API_IMAGE_DIGEST <sha256-digest-without-prefix>
```
Redeploy enabling app:
```
azd up
```

### 6.5 Switch to Explicit DNS (Optional Hardening)
1. Discover zone name:
```
az network private-dns zone list -g <rg> --query "[?starts_with(name,'internal.')].name" -o tsv
```
2. Update params: `internalAcaDnsMode=explicit`, `internalAcaDnsZoneName=<value>`
3. Redeploy `azd up`.

### 6.6 Integrate APIM (If External VNet)
- Ensure VNet peering both directions.
- Add APIM VNet ID to `additionalInternalAcaDnsVnetIds` to auto-link zone.
- Or manually link zone (see `DEPLOYMENT_STEPS.md` §9).

---
## 7. Image Packaging & Tagging Strategy
| Strategy | Command | Purpose |
|----------|---------|---------|
| Mutable latest | `az acr build -t citadel-api:latest ...` | Fast iteration |
| Immutable commit tag | `-t citadel-api:$(git rev-parse --short HEAD)` | Traceability |
| Digest pin (preferred for prod) | Use `image@sha256:<digest>` in Bicep/env | Rollback safety |

Revision suffix for updates (single revision mode):
```
az containerapp update -n aca-<suffix> -g <rg> --image <loginServer>/citadel-api:latest --revision-suffix researchonly
```

---
## 8. Internal DNS & ACA Domain Strategy
| Mode | Pros | Cons | When |
|------|------|------|------|
| auto | Zero config, quick start | Deployment script dependency, non-deterministic zone output initially | First deployment |
| explicit | Deterministic outputs, no script | Requires manual discovery once | Long-lived envs |
| none | External DNS control | Must manually create records | Rare / advanced |

APIM Resolution Requirements:
1. VNet peering established.
2. APIM VNet linked to internal ACA private zone.
3. A record present for `aca-<suffix>` (auto module or manual if script missed).

---
## 9. VNet Peering & Connectivity
Minimum: Bidirectional peering between primary app VNet and APIM VNet with `allow-vnet-access=true` both ways. Latency validation: `nslookup <app-fqdn>` from APIM test console (self-hosted gateway node or jump host) and initial `curl` to `/research`.

Codify peering after validation by adding APIM VNet ID to parameters and enabling reverse peering script flag (if implemented).

---
## 10. API Surface (Current State)
| Path | Method | Auth (future) | Description |
|------|--------|---------------|-------------|
| `/` | GET | Internal (VNet) | Landing & metadata |
| `/research` | POST | (Planned MI / token) | Research operation placeholder |
| `/researcher/research` | POST | Same | Backward-compatible alias; may deprecate |

Removed legacy: `/search`, `/researcher/search`.

---
## 11. Configuration & Secrets Handling
All sensitive references resolved at deploy time into environment variables (managed identity + connection strings). Avoid embedding keys in code. Use managed identity for data plane where supported; Bing API key is the exception (store via parameter / Key Vault integration—future enhancement).

Key runtime vars (sample):
- `AZURE_AI_PROJECT_CONNECTION_STRING`
- `APPLICATIONINSIGHTS_CONNECTION_STRING`
- `ENABLE_AZURE_MONITOR_TRACING` (false until private ingestion stable)
- `BING_SEARCH_API_KEY` (replace with secure reference)

---
## 12. Monitoring & Observability
Planned / existing instrumentation (see `MONITORING_INTEGRATION.md`):
- OpenTelemetry auto instrumentation via `azure-monitor-opentelemetry` (spans for request + streaming).
- Private endpoints for `monitor`, `oms`, `ods`, `agentsvc` zones ensuring no public egress.
- Action Item: confirm monitoring private endpoints deployed; if not, set parameter `enableMonitoringPrivateEndpoints=true` (or equivalent in module) and redeploy.
- After DNS resolves ingestion endpoint internally, set `ENABLE_AZURE_MONITOR_TRACING=true`.

Dashboards: Build Application Map (requests), custom query for research latency once implemented.

---
## 13. Security Controls Summary
| Control | Mechanism |
|---------|-----------|
| Network Isolation | Private endpoints + internal ingress |
| Identity | System-managed identity (consider future UAI) |
| Secret Minimization | No inline secrets except Bing key (to migrate) |
| RBAC | Role assignment modules for Storage/Cosmos/Search |
| Image Pull | MI + ACR `AcrPull` role; no admin user |
| Supply Chain (Future) | Digest pinning, optional signing |
| Egress Minimization | Only required private endpoints + Bing external call |

---
## 14. Operational Runbook (Common Tasks)
| Task | Command / Action |
|------|------------------|
| Build & deploy code change | ACR build → `containerapp update` with revision suffix |
| Rollback | Redeploy prior digest with new suffix (e.g. `rollback`) |
| Rotate Bing key | Update parameter / Key Vault secret (future) → `azd up` |
| Add new endpoint | Modify `src/main.py` → build → update → adjust APIM |
| Enable tracing | Ensure monitoring PEs success → set env var true → redeploy |
| Switch DNS mode | Capture zone → set explicit params → redeploy |
| Peering new consumer VNet | Add its VNet ID to zone links → (optional) codify param |

---
## 15. Troubleshooting Matrix (Derived from Phases)
| Symptom | Root Cause (Phase) | Resolution |
|---------|--------------------|-----------|
| 404 via APIM | Path rewrite mismatch (Phase 4) | Align APIM backend path; remove stale aliases |
| 404 internal | Ingress targetPort mismatch (Phase 2) | Recreate ingress with correct 8000 mapping |
| Crash on startup | Invalid import (Phase 2) | Remove unsupported library / fix dependency |
| DNS failures in traces | No private ingestion endpoint (Phase 3) | Deploy monitoring private endpoints or disable tracing |
| Legacy path still called | Client stale use of /search (Phase 5/6) | Communicate deprecation; remove old route |
| APIM cannot resolve FQDN | Missing zone link / record (Phase 1 manual) | Link APIM VNet + ensure A record exists |

---
## 16. Future Enhancements
| Category | Item | Benefit |
|----------|------|--------|
| Reliability | Liveness & readiness probes | Faster failure detection |
| Security | Key Vault integration for Bing key | Central secret governance |
| Observability | Enable tracing with private ingestion | Full distributed visibility |
| Supply Chain | Image signing & policy gate | Tamper resistance |
| Performance | Async research execution workers | Scalability |
| Governance | CI/CD pipeline (GitHub Actions + `azd deploy`) | Automation & consistency |
| DNS | Enforce explicit mode from start | Deterministic outputs |
| API | Replace placeholder logic with real research graph | Functional value |

---
## 17. Parameter Reference (Selected)
| Parameter | Description | Notes |
|-----------|-------------|-------|
| `stableSuffix` | Short deterministic suffix cluster | Used in resource names |
| `createContainerApp` | Toggle infra-only pass | Two-phase support |
| `containerAppIngressType` | `internal` or `external` | Should remain `internal` for this use case |
| `internalAcaDnsMode` | `auto` / `explicit` / `none` | Promote to `explicit` after discovery |
| `internalAcaDnsZoneName` | Internal zone FQDN | Required when explicit |
| `additionalInternalAcaDnsVnetIds` | Extra VNet IDs | For APIM / shared services |
| `enableMonitoringPrivateEndpoints` | Deploy monitoring PEs | Ensure true before enabling tracing |
| `API_IMAGE_DIGEST` (env) | Digest for image pin | Optional hardened deploy |

---
## 18. Revision & Rollback Strategy
Single revision mode means each update fully replaces traffic. Use descriptive suffixes:
- `researchonly`, `add-foo-endpoint`, `rollback`.
Store last known good digest externally (pipeline artifact) for fast rollback. Consider adding output exposure of active digest in Bicep.

---
## 19. Change Log (Phases Summary)
| Phase | Focus | Outcome |
|-------|-------|---------|
| 1 | Initial networking & DNS | Private ACA env reachable internally |
| 2 | 404 & crash resolution | Correct port + removed failing import |
| 3 | Runtime stabilization | Identified tracing DNS issue (monitoring gap) |
| 4 | API aliasing strategy | Added /researcher/* alignment for APIM |
| 5 | Endpoint rename plan | Introduced /research with compatibility |
| 6 | Legacy removal | Dropped /search, simplified surface |
| 7 | Documentation | Added `DEVELOPMENT.md` workflow |
| 8 | Monitoring expansion planning | Reviewed App Insights PE path |
| 9 | Stability inquiry | Confirmed DNS/peering unaffected by monitoring PEs |

---
## 20. Validation Checklist (Greenfield)
| Step | Complete? |
|------|-----------|
| Providers registered | [] |
| `azd up` (auto DNS) success | [] |
| Internal zone present / discovered | [] |
| APIM VNet linked (if needed) | [] |
| Image built and deployed | [] |
| /research functional via APIM | [] |
| Switch to explicit DNS (optional) | [] |
| Monitoring PEs deployed | [] |
| Tracing enabled (post-PE) | [] |
| Digest pinned for prod | [] |

---
## 21. Appendix A: Manual Commands (Quick Reference)
Build image:
```
az acr build -t citadel-api:latest -r <acr> ./src
```
Update container app:
```
az containerapp update -n aca-<suffix> -g <rg> --image <acr>.azurecr.io/citadel-api:latest --revision-suffix researchonly
```
List internal zones:
```
az network private-dns zone list -g <rg> -o table
```
Link APIM VNet to zone:
```
az network private-dns link vnet create -g <rg> -z <zone> -n apim-link -v <apimVnetId> -e false
```
Check logs:
```
az containerapp logs show -n aca-<suffix> -g <rg> --tail 50
```

---
## 22. Appendix B: Risk Register (Initial)
| Risk | Impact | Mitigation |
|------|--------|------------|
| Monitoring traffic blocked | Loss of tracing | Deploy monitoring PEs, verify DNS |
| Stale APIM rewrite rules | 404s | Align route mapping after endpoint changes |
| Unpinned image | Drift, hard rollback | Adopt digest pin in production |
| Manual DNS drift | Resolution failures | Switch to explicit mode + IaC zone outputs |
| Bing key leakage | Compromise search capability | Move to Key Vault reference |

---
## 23. Document Ownership & Maintenance
Primary owners: Platform / Infra team. Update this document whenever: new endpoint pattern, DNS mode policy change, monitoring architecture shifts, or security posture enhancements (e.g., signing) are adopted.

---
**End of Document**

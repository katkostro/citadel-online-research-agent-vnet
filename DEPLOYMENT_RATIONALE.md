# Citadel Research Agent Deployment Rationale

## Purpose
This document explains *why* the infrastructure was designed and evolved the way it did: privacy-first, deterministic, two-phase deployment enabling controlled rollout of an Azure AI Agent + supporting services inside a fully isolated virtual network.

## Guiding Principles
1. Network Isolation First – Every dependent Azure service (AI Foundry Account, AI Search, Cosmos DB, Storage, Bing Search (optional), Container Apps) restricted to private access via Private Endpoints or internal ingress.
2. Deterministic Naming – Stable 4‑char `stableSuffix` to reuse resources across redeploys (prevents accidental duplication and DNS churn).
3. Two-Phase Delivery – Allow infra provisioning (`createContainerApp=false`) before application image is available; flip to `true` only when image exists in ACR.
4. Progressive DNS Enablement – Internal ACA DNS introduced safely via master toggle + mode (auto → explicit later) to avoid template failures when default domain not yet known.
5. Principle of Least Privilege – User-assigned managed identity + `AcrPull`; no ACR admin user; future hardening path (disable public ACR, private endpoint, retention policy, scanning).
6. Idempotence – Repeated `azd up` does not create duplicates; modules handle existing-vs-new logic.

## Evolution Timeline
| Phase | Issue / Goal | Change Applied | Outcome |
|-------|--------------|----------------|---------|
| 1 | Baseline private infra | Core VNet + subnets + AI services + storage + search + cosmos | Private service backbone established |
| 2 | Monitoring private endpoints failing (preview constraint) | Temporarily disabled those PEs | Unblocked deployments |
| 3 | Need optional deferred app | Added `createContainerApp` param | Enabled two-phase flow |
| 4 | Internal ACA DNS template errors (empty zone) | Introduced `internalAcaDnsEnabled` master toggle & guarded logic | Avoided invalid ARM template states |
| 5 | Container App failed (image missing) | Built & pushed image to ACR | Successful revision rollout |
| 6 | Immediate DNS need w/ app | Enabled auto DNS (deployment script) + toggle | Internal zone provisioned automatically |
| 7 | Resource duplication risk | Aligned `stableSuffix` to existing (`6jjr`) | Reused assets cleanly |

## Internal Container Apps DNS Strategy
- Auto Mode: First deploy discovers `defaultDomain`, creates `internal.<defaultDomain>` zone (script). Fast start, but zone name implicit.
- Explicit Mode (future): After discovery, set `internalAcaDnsMode=explicit` + `internalAcaDnsZoneName` to stabilize zone identity (supports peering / APIM / cross-env reuse).
- Master Toggle: `internalAcaDnsEnabled` prevents any DNS artifacts until intentionally activated.

## Why Two-Phase (`createContainerApp`)
| Concern | Without Two-Phase | With Two-Phase |
|---------|-------------------|---------------|
| Image not yet built | Deployment fails (manifest unknown) | Infra succeeds; app added later |
| Secrets / env maturity | Must finalize early | Can refine before app deploy |
| Digest pinning | Harder to enforce upfront | Build → capture digest → redeploy |

## ACR Security Rationale
- Disable admin user → no shared creds leakage.
- Managed Identity pull → auditable principal.
- (Planned) Public network access -> Disabled + private endpoint + ACR private DNS zone.
- Digest over tag → prevents tag race / supply-chain substitution.

## Outputs & Consumption
Key outputs (from `main.bicep`):
- `SERVICE_API_NAME`, `SERVICE_API_URI` (placeholder pattern), actual ingress FQDN retrieved via CLI.
- `ACA_INTERNAL_DNS_ZONE` (explicit mode only) enabling deterministic internal DNS planning.
- AI Project + Storage + Search + Cosmos endpoints for app runtime environment variables.

## Trade-Offs
| Choice | Benefit | Trade-off |
|--------|---------|----------|
| Auto DNS first | Zero friction | Requires later switch for determinism |
| Internal-only ingress | Private exposure only | Requires APIM or internal client path |
| Two-phase app creation | Eliminates early image dependency | Extra deploy step |
| Stable suffix override | Reuse infra | Risk of accidental mismatch if wrong value chosen |

## Future Hardening Roadmap
1. Switch DNS to explicit mode (set `internalAcaDnsZoneName`).
2. Disable ACR public access & ensure private endpoint path tested.
3. Add image retention + vulnerability scanning + optional quarantine.
4. Pin deployments to digest via `containerImageDigest` param.
5. Re-enable monitoring private endpoints once feature readiness confirmed.
6. Introduce APIM (internal VNet) as north-south policy & auth layer.
7. Add CI pipeline enforcing security gates (lint, scan, test, sign, deploy).

## Summary
The deployment intentionally front-loaded *network isolation* and *determinism*, deferring app runtime specifics until the container artifact existed. The DNS strategy balances early productivity (auto) with a clear path to deterministic explicit naming. Identity-based ACR pulls and modular Bicep organization set the stage for incremental hardening without disruptive refactors.

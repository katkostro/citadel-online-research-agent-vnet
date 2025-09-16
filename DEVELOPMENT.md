# Development Workflow

This document describes how to add or modify API endpoints and redeploy the Citadel Online Research Agent running in Azure Container Apps (private VNet).

## 1. Prerequisites
- Azure CLI installed and logged in (`az login`)
- Sufficient RBAC permissions on resource group `rg-citadel6-in-vnet`
- Access to ACR `acr6jjr`
- Active branch (create feature branch from `master` or current working branch)

## 2. Add or Modify an Endpoint
1. Edit `src/main.py`.
2. Define a new Pydantic model if the request/response schema changes (place near existing `Message` model).
3. Add a FastAPI route decorator (e.g. `@app.post("/my-endpoint", tags=["search"])`).
4. Keep the handler small; delegate heavier logic to an internal helper function.
5. Add/adjust OpenAPI documentation: summary, description, and example response (`responses={...}`).
6. If removing endpoints, also: 
   - Update the landing page (`index` function) endpoint list.
   - Remove obsolete aliases.
7. Maintain naming consistency: use verbs for actions (`/research`, `/chat`) and avoid deprecated synonyms.

## 3. Local Static Validation (Optional)
Although the environment is container-first, you can do a quick syntax check locally:
```
python -m py_compile src/main.py
```
(Ensure dependencies from `src/requirements.txt` are available if you run locally.)

## 4. Build a New Image
From repo root:
```
az acr build -t citadel-api:latest -r acr6jjr ./src
```
Capture the resulting image digest (displayed at end of build). For immutable deployment pinning you can also tag with the short git SHA:
```
az acr build -t citadel-api:$(git rev-parse --short HEAD) -r acr6jjr ./src
```

## 5. Deploy to Azure Container Apps
Update the running container app with the new image. Use a unique revision suffix for traceability:
```
az containerapp update \
  -n aca-6jjr \
  -g rg-citadel6-in-vnet \
  --image acr6jjr.azurecr.io/citadel-api:latest \
  --revision-suffix <short-change-name>
```
Example:
```
az containerapp update -n aca-6jjr -g rg-citadel6-in-vnet --image acr6jjr.azurecr.io/citadel-api:latest --revision-suffix add-endpoint-x
```

Because the app is set to `Single` revision mode, 100% traffic automatically shifts to the newest revision.

## 6. Verify Deployment
1. Fetch logs:
```
az containerapp logs show -n aca-6jjr -g rg-citadel6-in-vnet --revision aca-6jjr--<suffix> --tail 50
```
2. (If curl available inside VNet) invoke the endpoint via APIM or internal DNS FQDN:
```
POST https://<apim-domain>/<path-in-apim>/research
```
3. Confirm no 404 and JSON structure matches expectations.

## 7. Update APIM (If Needed)
- If you added a brand new backend path, ensure the APIM operation points to `/research` (or new path) without stale rewrite rules.
- Remove obsolete operations if an endpoint was deleted.

## 8. Observability
Tracing currently emits DNS failures if outbound to Application Insights is blocked. To disable tracing set env var `ENABLE_AZURE_MONITOR_TRACING=false` in the Container App definition (Bicep or manual update) until private ingestion is configured.

## 9. Clean Up / Housekeeping
- Commit changes:
```
git add src/main.py README.md DEVELOPMENT.md
git commit -m "feat: add <endpoint-name> endpoint"
```
- Open a Pull Request and merge after review.
- Optionally retag image with digest in IaC (future enhancement) for deterministic rollbacks.

## 10. Rollback Procedure
If the new revision misbehaves:
1. Re-deploy the previous known-good image digest:
```
az containerapp update -n aca-6jjr -g rg-citadel6-in-vnet --image acr6jjr.azurecr.io/citadel-api@sha256:<old-digest> --revision-suffix rollback
```
2. Validate logs again.

## 11. Adding Health / Readiness Enhancements (Future)
Add probes to `modules/aca/container-app.bicep` (not yet present) for quicker failure detection:
```
// Pseudo-snippet (add under template.containers)
// livenessProbe: { httpGet: { path: "/health", port: 8000 }, initialDelaySeconds: 10, periodSeconds: 30 }
```
(Implement using official Bicep schema for Container Apps when ready.)

## 12. Checklist Summary
- [ ] Route added/modified in `main.py`
- [ ] Index landing JSON updated
- [ ] OpenAPI docs updated
- [ ] Image built (record digest)
- [ ] Container App updated with new revision suffix
- [ ] APIM route/operation aligned
- [ ] Logs verified (startup + first request)
- [ ] PR merged

## 13. Common Pitfalls
| Issue | Cause | Resolution |
|-------|-------|-----------|
| 404 via APIM | Path mismatch or stale rewrite | Inspect APIM trace; ensure backend URL matches Container App path |
| Container returns 404 | targetPort mismatch | Confirm ingress targetPort=8000 and app listens on 8000 |
| ImportError on startup | Missing / renamed SDK symbols | Pin versions and avoid importing preview internals |
| Tracing DNS failures | No outbound DNS/egress allowed | Disable tracing or configure private link ingestion |
| Stale code after deploy | Image cached or wrong tag | Verify digest printed after build and used in update command |

## 14. Example End-to-End (Add /foo)
```
# 1. Edit src/main.py add @app.post("/foo") handler
# 2. Build
az acr build -t citadel-api:latest -r acr6jjr ./src
# 3. Deploy
az containerapp update -n aca-6jjr -g rg-citadel6-in-vnet --image acr6jjr.azurecr.io/citadel-api:latest --revision-suffix foo
# 4. Verify logs
az containerapp logs show -n aca-6jjr -g rg-citadel6-in-vnet --revision aca-6jjr--foo --tail 50
# 5. Test through APIM
curl -X POST https://<apim-domain>/research/foo -d '{"message":"test"}'
```

---
Maintainer Notes: Keep this file updated when deployment tooling or infra patterns evolve (e.g., probes, pinned digests, CI/CD).

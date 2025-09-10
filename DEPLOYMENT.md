# Deployment Guide

This guide covers the deployment process for the Citadel Online Research Agent with VNet security.

## Overview

The application deploys as a VNet-secured AI research agent with the following components:
- **Container Apps**: FastAPI application with flexible ingress configuration
- **VNet Security**: Private endpoints for all Azure services
- **AI Services**: Azure AI Project with GPT-4o and text-embedding-3-small models
- **Search Integration**: Bing Grounding for web search capabilities
- **Monitoring**: Application Insights with comprehensive telemetry
- **Storage**: Cosmos DB and Azure Storage with private connectivity

## Prerequisites

1. **Azure CLI**: Install and authenticate with `az login`
2. **Azure Developer CLI**: Install azd from [aka.ms/azd](https://aka.ms/azd)
3. **Resource Provider Registration**: Ensure the following providers are registered:
   - Microsoft.App (Container Apps)
   - Microsoft.ContainerRegistry
   - Microsoft.Bing (for Bing Grounding)
   - Microsoft.CognitiveServices
   - Microsoft.DocumentDB
   - Microsoft.Storage

## Deployment Methods

### Standard Deployment (External Access)

The default deployment creates a Container App accessible from the internet while maintaining VNet security for all backend services.

```powershell
# Initialize the environment (first time only)
azd init

# Deploy with default external ingress
azd up
```

This configuration:
- ✅ Container App accessible via public internet
- ✅ All backend services secured with private endpoints
- ✅ VNet integration for Container Apps
- ✅ Application Insights telemetry enabled

### Secure Deployment (Internal Access Only)

For maximum security, deploy with internal-only Container App access:

```powershell
# Deploy with internal ingress (VNet-only access)
azd up --parameter containerAppIngressType=internal
```

This configuration:
- ✅ Container App only accessible within VNet
- ✅ Complete network isolation
- ✅ All services behind private endpoints
- ✅ Requires VNet connectivity for access (VPN, ExpressRoute, or Bastion)

## Container App Ingress Configuration

The deployment supports flexible ingress configuration through the `containerAppIngressType` parameter:

### External Ingress (Default)
```yaml
Parameter: containerAppIngressType=external
Access: Internet-accessible with VNet-secured backends
Use Case: Development, testing, external API access
Security: Medium-high (application exposed, backends secured)
```

### Internal Ingress
```yaml
Parameter: containerAppIngressType=internal
Access: VNet-only access
Use Case: Production, enterprise environments, maximum security
Security: High (complete network isolation)
```

## Deployment Architecture

### Network Security
- **VNet Integration**: Container Apps deployed with VNet integration
- **Private Endpoints**: All Azure services use private connectivity
- **Subnet Isolation**: Dedicated subnets for Container Apps and private endpoints
- **DNS Resolution**: Private DNS zones for service resolution

### Application Components
- **FastAPI Backend**: `/chat` and `/search` endpoints with full telemetry
- **AI Integration**: Azure AI Project with model deployments
- **Search Capabilities**: Bing Grounding for web research
- **Monitoring**: Application Insights with OpenTelemetry tracing

### Data Services
- **Cosmos DB**: Document storage with private endpoint
- **Azure Storage**: Blob storage with private connectivity
- **Container Registry**: Private registry for container images

## Environment Variables

The deployment automatically configures the following environment variables:

```yaml
# AI Services
AZURE_AI_PROJECT_CONNECTION_STRING: # Auto-configured from AI Project
AZURE_OPENAI_ENDPOINT: # Auto-configured from deployment

# Search Integration
BING_SEARCH_API_KEY: # Auto-configured from Bing resource

# Monitoring
APPLICATIONINSIGHTS_CONNECTION_STRING: # Auto-configured from App Insights

# Storage
AZURE_STORAGE_CONNECTION_STRING: # Auto-configured from Storage Account
COSMOS_DB_CONNECTION_STRING: # Auto-configured from Cosmos DB
```

## Idempotent Deployments

The infrastructure uses stable resource naming to support updates without duplication:

```bicep
// Stable naming pattern
uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 4)
```

Running `azd up` multiple times will:
- ✅ Update existing resources
- ✅ Maintain consistent naming
- ✅ Preserve data and configurations
- ❌ Not create duplicate resources

## Monitoring and Observability

### Application Insights Integration
- **Request Tracing**: All API requests tracked with correlation IDs
- **Custom Metrics**: Search performance and AI model usage
- **Error Tracking**: Comprehensive exception logging
- **Performance Monitoring**: Response times and resource usage

### Health Checks
- **Application Health**: `/health` endpoint for Container App monitoring
- **Service Dependencies**: AI services, storage, and search connectivity
- **Network Connectivity**: Private endpoint health validation

## Security Considerations

### Network Security
- All inter-service communication uses private connectivity
- Container Apps can be configured for internal-only access
- VNet integration provides network-level isolation
- Private DNS ensures secure service resolution

### Authentication & Authorization
- Managed Identity for Azure service authentication
- API key authentication for Bing Search
- No credential storage in application code
- Secure configuration through Azure Key Vault integration

### Data Protection
- Encryption at rest for all storage services
- TLS encryption for all communications
- Private endpoint encryption for data transfer
- Cosmos DB with automatic encryption

## Troubleshooting

### Common Issues

**1. Resource Provider Not Registered**
```powershell
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.Bing
```

**2. Insufficient Quota**
Check quota availability before deployment:
```powershell
az vm list-usage --location eastus
```

**3. Private Endpoint DNS Resolution**
Verify private DNS zones are properly linked to VNet:
```powershell
az network private-dns zone list --resource-group <rg-name>
```

**4. Container App Access Issues**
- **External ingress**: Check firewall rules and NSG configurations
- **Internal ingress**: Ensure VNet connectivity (VPN/ExpressRoute)
- **Application logs**: Use `az containerapp logs show` for debugging

### Validation Steps

After deployment, validate the configuration:

```powershell
# Check Container App status
az containerapp show --name <app-name> --resource-group <rg-name>

# Test health endpoint
curl https://<app-url>/health

# Verify private endpoints
az network private-endpoint list --resource-group <rg-name>

# Check Application Insights connectivity
az monitor app-insights component show --app <app-name> --resource-group <rg-name>
```

## Cleanup

To remove all deployed resources:

```powershell
azd down
```

This will remove:
- Resource group and all contained resources
- VNet and associated networking components
- Storage accounts and data (⚠️ **Data loss warning**)
- AI model deployments and configurations

## Support and Documentation

- **Network Security**: See [NETWORK_SECURITY_COMPLIANCE.md](./NETWORK_SECURITY_COMPLIANCE.md)
- **Monitoring Setup**: See [MONITORING_INTEGRATION.md](./MONITORING_INTEGRATION.md)
- **Bing Integration**: See [BING_SEARCH_INTEGRATION.md](./BING_SEARCH_INTEGRATION.md)
- **Azure Container Apps**: [Official Documentation](https://docs.microsoft.com/azure/container-apps/)
- **Azure AI Studio**: [Official Documentation](https://docs.microsoft.com/azure/ai-studio/)

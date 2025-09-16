# Application Insights and Log Analytics Integration

## Overview
This document describes the comprehensive monitoring solution added to the network-secured Azure AI Foundry environment, matching the capabilities from the original repository at https://github.com/katkostro/citadel-online-researcher-agent/tree/main.

## Components Added

### 1. Infrastructure Components

#### Application Insights Module (`modules-network-secured/application-insights.bicep`)
- **Application Insights**: Web application monitoring with connection string and instrumentation key
- **Log Analytics Workspace**: Centralized logging with 30-day retention and PerGB2018 pricing tier
- **Private Endpoints**: Network isolation for monitoring services with 4 DNS zones:
  - `privatelink.monitor.azure.com`
  - `privatelink.oms.opinsights.azure.com`
  - `privatelink.ods.opinsights.azure.com`
  - `privatelink.agentsvc.azure-automation.net`
- **Private DNS Zones**: VNet integration with conditional existing zone support
- **Network Security**: Full compliance with VNet architecture

#### Main Infrastructure Integration (`main.bicep`)
- Application Insights module deployment
- Container app integration with monitoring parameters
- Monitoring outputs for connection strings and workspace IDs

#### Container App Enhancement (`modules-network-secured/container-app.bicep`)
- Integration with shared Log Analytics workspace
- Application Insights environment variables:
  - `APPLICATIONINSIGHTS_CONNECTION_STRING`
  - `APPINSIGHTS_INSTRUMENTATIONKEY`
  - `ENABLE_AZURE_MONITOR_TRACING`
  - `AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED`

### 2. Application Components

#### Python Application Tracing (`src/main.py`)
- **Azure Monitor OpenTelemetry**: Complete integration using `configure_azure_monitor`
- **OpenTelemetry Tracer**: Application-wide tracing with service attributes
- **Distributed Tracing**: TraceContextTextMapPropagator for request correlation
- **Comprehensive Span Management**:
  - Health check endpoint tracing
  - Chat endpoint tracing with distributed context
  - Stream response tracing with nested spans
  - Error recording and status management

#### Dependencies (`requirements.txt`)
- `azure-monitor-opentelemetry>=1.0.0`
- `opentelemetry-api>=1.21.0`
- `opentelemetry-sdk>=1.21.0`

## Key Features

### Network Security
- All monitoring services secured with private endpoints
- VNet-integrated DNS resolution
- No public internet access required for telemetry

### Comprehensive Tracing
- **Service-Level Attributes**:
  - `service.name`: AI Research Agent
  - `service.version`: 1.0.0
  - `service.instance.id`: Environment-specific
- **GenAI Content Recording**: Enabled for AI interaction monitoring
- **Distributed Tracing**: Request correlation across components
- **Custom Spans**: Detailed tracing for chat, streaming, and health operations

### Monitoring Capabilities
- Real-time application performance monitoring
- Centralized log aggregation and analysis
- Custom telemetry and metrics collection
- Error tracking and exception monitoring
- AI interaction monitoring with content recording

## Environment Variables
The following environment variables are automatically configured:

```bash
APPLICATIONINSIGHTS_CONNECTION_STRING=<Application Insights Connection String>
APPINSIGHTS_INSTRUMENTATIONKEY=<Application Insights Instrumentation Key>
ENABLE_AZURE_MONITOR_TRACING=true
AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED=true
```

## Deployment
The monitoring solution is fully integrated with the existing infrastructure and will be deployed automatically with `azd up`.

## Infrastructure Outputs
- `APPLICATION_INSIGHTS_CONNECTION_STRING`: For application configuration
- `APPLICATION_INSIGHTS_INSTRUMENTATION_KEY`: For legacy SDK compatibility
- `LOG_ANALYTICS_WORKSPACE_ID`: For log correlation

## Compliance
- Network-secured architecture maintained
- Private endpoint compliance
- VNet integration requirements satisfied
- Original repository feature parity achieved

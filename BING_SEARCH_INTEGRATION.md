# Bing Search Integration - Network Secured Environment

## Overview
Complete Bing Search integration has been successfully added to the network-secured Azure AI Foundry environment, providing comprehensive web search capabilities with AI-powered analysis.

## Infrastructure Components Added

### 1. Bing Search Module (`modules-network-secured/bing-search.bicep`)
- **Bing Search Resource**: Cognitive Services account with Bing.Search.v7 kind
- **Private Endpoint**: Network isolation for secure access
- **Private DNS Zone**: `privatelink.cognitiveservices.azure.com` for name resolution
- **SKU Support**: F1 (free) and S1 (standard) tiers
- **VNet Integration**: Full integration with existing VNet architecture

### 2. Main Infrastructure Integration (`main.bicep`)
- **Parameters Added**:
  - `enableBingSearch` (default: true)
  - `bingSearchSku` (default: F1)
- **Module Deployment**: Conditional Bing Search module deployment
- **Container App Integration**: Environment variables for Bing Search configuration
- **Outputs**: Bing Search resource information and configuration status

### 3. Container App Enhancement (`modules-network-secured/container-app.bicep`)
- **Environment Variables**:
  - `ENABLE_BING_SEARCH`: Controls web search functionality
  - `BING_SEARCH_ENDPOINT`: API endpoint URL
  - `BING_SEARCH_API_KEY`: Secure API key configuration
- **Conditional Logic**: Union-based environment variable setup

## Application Components

### 1. Bing Grounding Tool (`src/api/bing_grounding_tool.py`)
- **BingGroundingTool Class**: Complete web search implementation
- **Async Search**: `search_web_async()` method using aiohttp
- **Fallback Handling**: Graceful degradation when API unavailable
- **Result Formatting**: Structured search result processing
- **Error Handling**: Comprehensive exception management
- **Configuration Detection**: Environment-based enablement

### 2. Search Endpoint (`src/main.py`)
- **POST /search**: Full-featured search endpoint
- **Request Format**: Uses existing `Message` model
- **AI Analysis**: Azure AI Foundry agent integration for result analysis
- **Response Format**: Standardized JSON with citations
- **OpenTelemetry Tracing**: Complete instrumentation
- **Error Handling**: Robust error responses and logging

### 3. Dependencies (`requirements.txt`)
- **aiohttp>=3.8.0**: HTTP client for Bing API calls

## Key Features

### Network Security
- **Private Endpoints**: All Bing Search traffic secured within VNet
- **DNS Integration**: Private DNS zone for internal name resolution
- **No Public Access**: Bing Search resource configured with public access disabled

### Search Capabilities
- **Real-time Web Search**: Current information retrieval
- **AI-Powered Analysis**: Intelligent result synthesis and summarization
- **Citation Formatting**: Unicode citations in format 【n:m†source】
- **Context-Aware**: Enhanced queries with additional context
- **Fallback Responses**: Helpful guidance when search unavailable

### Monitoring & Tracing
- **Full OpenTelemetry Integration**: Search endpoint instrumentation
- **Distributed Tracing**: Request correlation across components
- **Performance Metrics**: Search latency and success rate tracking
- **Error Tracking**: Comprehensive exception recording

## Configuration

### Environment Variables
```bash
# Bing Search Configuration
ENABLE_BING_SEARCH=true
BING_SEARCH_ENDPOINT=https://api.bing.microsoft.com/
BING_SEARCH_API_KEY=<your-api-key>

# Monitoring (already configured)
APPLICATIONINSIGHTS_CONNECTION_STRING=<connection-string>
ENABLE_AZURE_MONITOR_TRACING=true
```

### Deployment Parameters
```bash
# Enable Bing Search (default: true)
azd up --set enableBingSearch=true

# Use standard SKU instead of free tier
azd up --set bingSearchSku=S1
```

## API Usage

### Search Endpoint
```http
POST /search
Content-Type: application/json

{
  "message": "latest news about Azure AI",
  "session_state": {}
}
```

### Response Format
```json
{
  "response": {
    "type": "text",
    "text": {
      "value": "Based on my search, here are the latest updates about Azure AI...",
      "annotations": [
        {
          "type": "citation",
          "text": "【1:0†Microsoft Official Blog】",
          "start_index": 45,
          "end_index": 48,
          "citation": {
            "citation_id": "1:0",
            "quote": "Azure continues to expand...",
            "source_name": "Microsoft Official Blog"
          }
        }
      ]
    }
  }
}
```

## Security Considerations

### API Key Management
- Bing Search API key stored as container app secret
- Not exposed in deployment logs or environment
- Configured through Azure CLI after deployment

### Network Isolation
- All search traffic routed through private endpoints
- No external internet access required from container
- DNS resolution handled within VNet

### Access Control
- Search endpoint protected by existing auth_dependency
- Role-based access through Azure Identity
- Container app managed identity integration

## Post-Deployment Setup

### 1. Obtain Bing Search API Key
```bash
# Create Bing Search v7 resource in Azure Portal
# Copy API key from Keys and Endpoint page
```

### 2. Configure Container App Secret
```bash
# Set API key as container app secret
az containerapp secret set \
  --name <container-app-name> \
  --resource-group <resource-group> \
  --secrets bing-search-api-key=<your-api-key>

# Update environment variable
az containerapp update \
  --name <container-app-name> \
  --resource-group <resource-group> \
  --set-env-vars BING_SEARCH_API_KEY=secretref:bing-search-api-key
```

### 3. Restart Container App
```bash
az containerapp restart \
  --name <container-app-name> \
  --resource-group <resource-group>
```

## Testing

### Search Functionality
```bash
# Test search endpoint
curl -X POST "<app-url>/search" \
  -H "Content-Type: application/json" \
  -d '{"message": "current weather in Seattle", "session_state": {}}'
```

### Expected Behavior
- **With API Key**: Real-time web search results with AI analysis
- **Without API Key**: Helpful guidance and fallback responses
- **Network Issues**: Graceful degradation with user guidance

## Integration Complete
The Bing Search integration is now fully implemented and ready for deployment. The system provides:

✅ **Infrastructure**: Secure Bing Search resource with private endpoints  
✅ **Application**: Complete search endpoint with AI analysis  
✅ **Monitoring**: Full OpenTelemetry tracing integration  
✅ **Security**: Network-isolated configuration  
✅ **Flexibility**: Conditional deployment and graceful degradation  

Deploy with `azd up` and configure the API key to enable comprehensive web search capabilities!

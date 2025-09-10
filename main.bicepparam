using './main.bicep'

param location = 'eastus2'
param environmentName = 'dev'
param aiServices = 'citadelaiv2'
param modelName = 'gpt-4o'
param modelFormat = 'OpenAI'
param modelVersion = '2024-11-20'
param modelSkuName = 'GlobalStandard'
param modelCapacity = 30
param firstProjectName = 'project'
param projectDescription = 'A project for the AI Foundry account with network secured deployed Agent'
param displayName = 'project'
param peSubnetName = 'citadelai-pe-subnet'

// Resource IDs for existing resources
// If you provide these, the deployment will use the existing resources instead of creating new ones
param existingVnetResourceId = ''
param vnetName = 'citadelai-vnet'
param agentSubnetName = 'citadelai-apps-subnet'
param aiSearchResourceId = ''
param azureStorageAccountResourceId = ''
param azureCosmosDBAccountResourceId = ''
// Pass the DNS zone map here
// Leave empty to create new DNS zone, add the resource group of existing DNS zone to use it
param existingDnsZones = {
  'privatelink.services.ai.azure.com': ''
  'privatelink.openai.azure.com': ''
  'privatelink.cognitiveservices.azure.com': ''               
  'privatelink.search.windows.net': ''           
  'privatelink.blob.core.windows.net': ''                            
  'privatelink.documents.azure.com': ''
  'privatelink.monitor.azure.com': ''
  'privatelink.oms.opinsights.azure.com': ''
  'privatelink.ods.opinsights.azure.com': ''
  'privatelink.agentsvc.azure-automation.net': ''                       
}

//DNSZones names for validating if they exist
param dnsZoneNames = [
  'privatelink.services.ai.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.cognitiveservices.azure.com'
  'privatelink.search.windows.net'
  'privatelink.blob.core.windows.net'
  'privatelink.documents.azure.com'
  'privatelink.monitor.azure.com'
  'privatelink.oms.opinsights.azure.com'
  'privatelink.ods.opinsights.azure.com'
  'privatelink.agentsvc.azure-automation.net'
]

// Network configuration: only used when existingVnetResourceId is not provided
// These addresses are only used when creating a new VNet and subnets
// If you provide existingVnetResourceId, these values will be ignored
// Leave empty to use automatic subnet sizing (/23 for Container Apps, /24 for Private Endpoints)
param vnetAddressPrefix = ''
param agentSubnetPrefix = ''
param peSubnetPrefix = ''

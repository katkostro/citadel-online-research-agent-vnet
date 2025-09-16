using './main.bicep'

param location = 'eastus2'
param environmentName = 'citadel6-in-vnet'
param modelName = 'gpt-4o'
param modelFormat = 'OpenAI'
param modelVersion = '2024-11-20'
param modelSkuName = 'GlobalStandard'
param modelCapacity = 30
param firstProjectName = 'citadelproject'
param projectDescription = 'A project for the AI Foundry account with network secured deployed Agent'
param displayName = 'project'
param peSubnetName = 'citadel6-pe-snet'

// Resource IDs for existing resources (blank => create new)
param existingVnetResourceId = ''
param vnetName = 'vnet-citadel6'
param agentSubnetName = 'citadel6-agent-snet'
param acaSubnetName = 'citadel6-aca-snet'
param aiSearchResourceId = ''
param azureStorageAccountResourceId = ''
param azureCosmosDBAccountResourceId = ''

// DNS zone map (blank values => create zones in this RG)
param existingDnsZones = {
	'privatelink.services.ai.azure.com': ''
	'privatelink.openai.azure.com': ''
	'privatelink.cognitiveservices.azure.com': ''
	'privatelink.search.windows.net': ''
	'privatelink.documents.azure.com': ''
	'privatelink.monitor.azure.com': ''
	'privatelink.oms.opinsights.azure.com': ''
	'privatelink.ods.opinsights.azure.com': ''
	'privatelink.agentsvc.azure-automation.net': ''
}

// DNS zone names list
param dnsZoneNames = [
	'privatelink.services.ai.azure.com'
	'privatelink.openai.azure.com'
	'privatelink.cognitiveservices.azure.com'
	'privatelink.search.windows.net'
	'privatelink.documents.azure.com'
	'privatelink.monitor.azure.com'
	'privatelink.oms.opinsights.azure.com'
	'privatelink.ods.opinsights.azure.com'
	'privatelink.agentsvc.azure-automation.net'
]

// Network configuration for new VNet
param vnetAddressPrefix = '172.29.0.0/16'
param agentSubnetPrefix = '172.29.0.0/24'
param peSubnetPrefix = '172.29.1.0/24'
param acaSubnetPrefix = '172.29.2.0/23'

// Two-phase toggle (true => create container app now)
param createContainerApp = true

// Optional deterministic suffix
// Optional deterministic suffix (uncomment & change if you need fixed naming)
// param stableSuffix = 'p7x1'

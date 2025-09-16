@description('Creates a Bing Search resource for web search capabilities')
param bingSearchName string
param tags object = {}

// Bing.Grounding is a global service and doesn't require VNet integration
// Interface compatibility parameters (not used but kept for consistency)
param vnetName string = ''
param subnetName string = ''
param dnsZoneResourceGroupName string = ''
param createDnsZones bool = true

// Bing Search resource (exactly like the working repository)
resource bingSearch 'Microsoft.Bing/accounts@2020-06-10' = {
  name: bingSearchName
  location: 'global'
  tags: tags
  kind: 'Bing.Grounding'
  sku: {
    name: 'G1'
  }
}

// Outputs
output bingSearchId string = bingSearch.id
output bingSearchName string = bingSearch.name
output bingSearchEndpoint string = 'https://api.bing.microsoft.com/'
